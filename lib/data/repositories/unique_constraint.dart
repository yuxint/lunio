// 唯一约束冲突的仓库边界类型化包装（顶层函数）。
//
// ≈ Java 全局异常处理器里的一条 translate 规则：把驱动层异常翻译成
// 业务异常。驱动异常产生在 drift/sqlite3 内部、无法在 throw 点改型
// （ADR 0009 原先因此靠 UI 层文本匹配兜底），但仓库写路径的边界可以
// try/catch 包住整段写库动作，在这里统一认型翻译（ADR 0009
// 2026-10-01 修订节）——改英文措辞、换数据库驱动或升级 Drift 都不再
// 影响错误分类。
//
// 驱动异常到达本边界时的两种形态（都要认，缺一就是生产回归）：
//  1. 直接的 [SqliteException]——进程内连接（NativeDatabase，测试与
//     AppDatabase.forFile 用）下异常实例原样上抛；
//  2. [DriftRemoteException]（remoteCause 才是 SqliteException）——
//     生产连接 NativeDatabase.createInBackground（app_database.dart
//     _openConnection）把 SQLite 跑在后台 isolate，语句异常经 drift
//     远程协议回传：服务端 isolate 把原始异常作为 ErrorResponse 发回
//     （serialize=false 时实例本身直传），客户端对每个 ErrorResponse
//     都无条件包成 DriftRemoteException（drift 2.33.0 src/remote/
//     communication.dart _handleMessage），与是否序列化无关——事务
//     回滚后 rethrow 的也是这层包装。
//
// 为什么是顶层函数而不是类：无状态、不持有数据库连接，主仓库与备份
// 仓库都要用（与 entity_row_codec.dart 同风格）。
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift/native.dart' show SqliteException;

import '../../domain/errors/lunio_error.dart';

/// SQLite 扩展结果码 SQLITE_CONSTRAINT_UNIQUE：唯一约束冲突。
/// 故意只认它、不认泛码 19（SQLITE_CONSTRAINT）——泛码还覆盖
/// NOT NULL/CHECK/外键，把那类程序 bug 误译成"这条数据已经保存过了"
/// 比落兜底文案更糟；与此前 UI 层文本匹配（只认 UNIQUE）语义等价。
const int _sqliteConstraintUnique = 2067;

/// 在仓库写路径的边界执行 [action]，把驱动层唯一约束冲突包装成
/// [LunioErrorKind.uniqueConstraint]（文案与 UI 层原兜底文案一致）；
/// 其余异常（含其他结果码的 SqliteException、remoteCause 非唯一约束
/// 冲突的 DriftRemoteException）原样透传，不吞不改。
///
/// 包装面 = 表单提交/恢复备份可直接撞唯一约束的仓库公开写入口
/// （主仓库的建车/编辑车/存项目/编辑项目/记录写管线，备份仓库的恢复
/// 事务）；读路径与不可能撞唯一约束的写路径（删除、不碰约束列的
/// 更新）不包。事务闭包抛异常时 drift 先回滚再上抛原始异常，本函数
/// 包在最外层即可覆盖整段事务。
Future<T> guardUniqueConstraint<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on SqliteException catch (error) {
    if (error.extendedResultCode == _sqliteConstraintUnique) {
      throw const LunioErrorException(
        LunioErrorKind.uniqueConstraint,
        '这条数据已经保存过了',
      );
    }
    rethrow;
  } on DriftRemoteException catch (error) {
    // 生产连接（后台 isolate 远程协议）形态：拆开 remoteCause 认型。
    // 真序列化连接（web/wasm）的 remoteCause 是序列化描述而非
    // SqliteException 实例，这里认不出、原样透传——本仓生产只有
    // 后台 isolate 连接，不在该场景内（ADR 0009 修订节边界注记）。
    final cause = error.remoteCause;
    if (cause is SqliteException &&
        cause.extendedResultCode == _sqliteConstraintUnique) {
      throw const LunioErrorException(
        LunioErrorKind.uniqueConstraint,
        '这条数据已经保存过了',
      );
    }
    rethrow;
  }
}

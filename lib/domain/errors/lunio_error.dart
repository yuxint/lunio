// 保存动作的业务错误类型（≈ Java 的业务异常体系：BusinessException +
// 错误码枚举）。
//
// 为什么要有类型：过去 Repository 抛"无类型异常 + 约定英文消息"，UI 的
// 错误翻译层（friendlyError）靠 `message.contains('英文子串')` 认领——
// 改一条英文措辞就会让对应文案静默退回兜底，编译期毫无报警。现在
// Repository 抛 [LunioErrorException]，kind 就是错误码，中文文案在
// throw 点就地书写（单一事实来源），翻译层只认类型、不再猜文本。
//
// 范围：只收"表单提交路径上需要翻译成行内提示的业务规则失败"。
// 数据库驱动层的异常里，只有唯一约束冲突进类型体系——不在 throw 点
// 包装（驱动异常产生在 drift/sqlite3 内部，改不了型），而是在仓库
// 写路径的边界经 data/repositories/unique_constraint.dart 的
// guardUniqueConstraint 统一翻译成 [LunioErrorKind.uniqueConstraint]
// （ADR 0009 2026-10-01 修订节）；其余驱动异常仍不建模，由 friendlyError
// 的兜底文案吸收。
import 'package:flutter/foundation.dart';

/// 业务失败类型（≈ 错误码枚举）。
enum LunioErrorKind {
  /// 同车同日已有保养记录（表级唯一约束 {carId,date} 的业务前置检查）。
  duplicateMaintenanceRecord,

  /// 撞数据库唯一约束（驱动层 SQLITE_CONSTRAINT_UNIQUE 2067 在仓库
  /// 写路径边界的类型化包装：表单提交或恢复备份写入重复数据、且没有
  /// 业务前置检查先拦下时的最后防线）。文案是通用兜底口径，具体哪张
  /// 表哪个键撞了不区分（与包装前的文本识别兜底同语义）。
  uniqueConstraint,

  /// 该车至少要保留一个启用的保养项目（停用/删除最后一个启用项）。
  lastEnabledMaintenanceItem,

  /// 保养项目已有历史记录，不能删除。
  maintenanceItemHasHistory,

  /// 记录引用的保养项目不存在（已被删除）。
  missingRecordItems,

  /// 记录引用了其他车辆的保养项目。
  itemFromAnotherCar,

  /// 备份文件不可恢复（恢复预校验在开事务前拦下：实体校验失败或
  /// 保养记录同车同日重复）。单一 kind 承载全部恢复拒绝，区分度在
  /// throw 点的中文文案里（ADR 0009 修订节）。
  backupInvalidData,
}

/// 业务规则失败异常：message 即用户可读中文，UI 直接展示。
@immutable
class LunioErrorException implements Exception {
  const LunioErrorException(this.kind, this.message);

  /// 失败类型（翻译与测试按它区分，不按文本区分）。
  final LunioErrorKind kind;

  /// 用户可读中文文案。
  final String message;

  @override
  String toString() => 'LunioErrorException($kind, $message)';
}

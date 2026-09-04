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
// 数据库驱动层的异常（如唯一约束 SqliteException 2067）不在此建模，
// 由 friendlyError 的约束识别兜底（无法在 throw 点包装驱动异常）。
import 'package:flutter/foundation.dart';

/// 业务失败类型（≈ 错误码枚举）。
enum LunioErrorKind {
  /// 同车同日已有保养记录（表级唯一约束 {carId,date} 的业务前置检查）。
  duplicateMaintenanceRecord,

  /// 该车至少要保留一个启用的保养项目（停用/删除最后一个启用项）。
  lastEnabledMaintenanceItem,

  /// 保养项目已有历史记录，不能删除。
  maintenanceItemHasHistory,

  /// 记录引用的保养项目不存在（已被删除）。
  missingRecordItems,

  /// 记录引用了其他车辆的保养项目。
  itemFromAnotherCar,
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

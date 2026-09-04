// 格式化与文案工具集（≈ Java 的 FormatUtil / MessageUtil）。
//
// 两类内容：
//  1. 纯格式化：数字千分位、里程、车龄、剩余天数、时刻 HH:mm:ss 等；
//  2. 业务文案：错误翻译 friendlyError（把 Repository 抛的英文异常
//     翻成中文）、唯一约束识别。
//
// 只保留"多文件复用"的函数（§5.2 回收口径）：单文件消费的格式化
// （金额、项目规则文案、提醒详情文案、项目名归一化等）已移回各自的
// 消费文件，避免这里的公共面无限膨胀。
import 'package:flutter/material.dart';

import '../../../core/date/local_date.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_default_maintenance_item.dart';
import '../../../domain/errors/lunio_error.dart';

/// 数字输入框的标准外观。
InputDecoration numberInputDecoration({String? labelText, String? suffixText}) {
  return InputDecoration(labelText: labelText, suffixText: suffixText);
}

/// 百分比文案（封顶 999%+，防止超期太多时撑爆 UI）。
String formatPercent(int percent) {
  return percent > 999 ? '999%+' : '$percent%';
}

/// 默认模板 → 车辆级项目实体（添加车辆向导草稿转换）。
/// carsId 填 0 占位，入库时由 Repository 换成真实车辆 id。
MaintenanceItem maintenanceItemFromDefault(
  VehicleDefaultMaintenanceItem item,
  SyncMetadata sync,
) {
  return MaintenanceItem(
    carsId: 0,
    name: item.itemName,
    enabled: true,
    remindByMileage: item.remindByMileage,
    remindByTime: item.remindByTime,
    mileageIntervalKm: item.mileageIntervalKm,
    timeIntervalMonths: item.timeIntervalMonths,
    notOverdueUpperLimit: item.notOverdueUpperLimit,
    overdueUpperLimit: item.overdueUpperLimit,
    sortOrder: item.sortOrder,
    sync: sync,
  );
}

/// 记录的项目名列表（按 itemIds 顺序查名，查不到显示"未知项目"）。
List<String> recordItemNameList(
  MaintenanceRecord record,
  List<MaintenanceItem> items,
) {
  return record.itemIds
      .map((id) => itemById(items, id)?.name ?? '未知项目')
      .toList();
}

/// 按 id 线性查找项目（列表小，不做索引）。
MaintenanceItem? itemById(List<MaintenanceItem> items, int itemId) {
  for (final item in items) {
    if (item.id == itemId) {
      return item;
    }
  }
  return null;
}

/// 里程 + 单位。
String formatMileageKm(int value) {
  return '${formatNumber(value)}km';
}

/// 车龄文案（上路日期至今的年数，1 位小数，不足半年显示如 0.5年）。
String formatCarAge(LocalDate roadDate, LocalDate today) {
  final months = roadDate.monthsUntil(today).clamp(0, 1200);
  final years = months / 12;
  final text = years.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$text年';
}

/// 时间维剩余文案（提醒详情用）。
String timeReminderText(int remainingDays) {
  if (remainingDays > 0) {
    return '时间：距离下次约 ${formatReminderDuration(remainingDays)}';
  }
  if (remainingDays == 0) {
    return '时间：今日到期';
  }
  return '时间：已超 ${formatReminderDuration(remainingDays.abs())}';
}

/// 剩余天数的友好时长（天/月/年+月）。
String formatReminderDuration(int days) {
  if (days < 30) {
    return '$days天';
  }
  if (days < 365) {
    return '${days ~/ 30}个月';
  }
  final months = days ~/ 30;
  final years = months ~/ 12;
  final restMonths = months % 12;
  if (restMonths == 0) {
    return '$years年';
  }
  return '$years年$restMonths个月';
}

/// 识别 SQLite 唯一约束冲突（消息文本匹配 2067），
/// 备份恢复冲突弹窗靠它区分文案。
bool isUniqueConstraintError(Object error) {
  final message = error.toString();
  return message.contains('UNIQUE constraint') ||
      message.contains('SqliteException(2067)');
}

/// 统一错误翻译（≈ ExceptionHandler 的消息转换）：业务规则失败认
/// [LunioErrorException] 类型，直接透出 throw 点书写的中文文案；
/// 数据库驱动层的唯一约束冲突（无法在 throw 点包装）按文本识别兜底；
/// 其余异常兜底"操作失败，请稍后重试"。全部表单的 catch 分支都走它。
String friendlyError(Object error) {
  if (error is LunioErrorException) {
    return error.message;
  }
  if (isUniqueConstraintError(error)) {
    return '这条数据已经保存过了';
  }
  return '操作失败，请稍后重试';
}

/// 日期的中文展示："2026年8月25日"。
String formatDateForUser(LocalDate date) {
  return '${date.year}年${date.month}月${date.day}日';
}

/// 数字千分位（12345 → "12,345"）。手写实现，未用 intl。
String formatNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final fromEnd = text.length - i;
    buffer.write(text[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

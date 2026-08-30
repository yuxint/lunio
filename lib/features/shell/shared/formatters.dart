// 格式化与文案工具集（≈ Java 的 FormatUtil / MessageUtil）。
//
// 两类内容：
//  1. 纯格式化：数字千分位、金额（分→元）、里程、车龄、剩余天数等；
//  2. 业务文案：错误翻译 friendlyError（把 Repository 抛的英文异常
//     翻成中文）、提醒规则文案、唯一约束识别。
//
// 全部是无状态顶层函数（≈ static 工具方法），被所有表单/列表复用。
import 'package:flutter/material.dart';

import '../../../core/date/local_date.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_default_maintenance_item.dart';

/// 数字输入框的标准外观。
InputDecoration numberInputDecoration({String? labelText, String? suffixText}) {
  return InputDecoration(labelText: labelText, suffixText: suffixText);
}

/// 进度环显示百分比的四舍五入钳制：真实进度没到阈值时，
/// 显示值不允许"看起来已到阈值"（如 99.6% 显示 99% 而不是 100%）。
int displayPercentForThresholds({
  required double percent,
  required double notOverdueUpperLimit,
  required double overdueUpperLimit,
}) {
  var display = percent.round();
  if (percent < notOverdueUpperLimit &&
      display >= notOverdueUpperLimit.ceil()) {
    display = notOverdueUpperLimit.ceil() - 1;
  }
  if (percent < overdueUpperLimit && display >= overdueUpperLimit.ceil()) {
    display = overdueUpperLimit.ceil() - 1;
  }
  return display;
}

/// 百分比文案（封顶 999%+，防止超期太多时撑爆 UI）。
String formatPercent(int percent) {
  return percent > 999 ? '999%+' : '$percent%';
}

/// 保养项目的规则文案："提醒：5000公里/6个月"（当前仅一处使用）。
String itemRuleText(MaintenanceItem item) {
  final rules = <String>[];
  if (item.remindByMileage) {
    rules.add(formatCompactMileageText(item.mileageIntervalKm ?? 0));
  }
  if (item.remindByTime) {
    rules.add(formatCompactTimeText(item.timeIntervalMonths ?? 0));
  }
  return rules.isEmpty ? '提醒：未设置' : '提醒：${rules.join('/')}';
}

/// 默认模板的规则文案（与 itemRuleText 逻辑重复，仅一处使用，R30/R32）。
String defaultItemRuleText(VehicleDefaultMaintenanceItem item) {
  final rules = <String>[];
  if (item.remindByMileage) {
    rules.add(formatCompactMileageText(item.mileageIntervalKm ?? 0));
  }
  if (item.remindByTime) {
    rules.add(formatCompactTimeText(item.timeIntervalMonths ?? 0));
  }
  return rules.isEmpty ? '提醒：未设置' : '提醒：${rules.join('/')}';
}

/// 项目名规范化（去首尾空白），项目表单保存前统一走它。
String normalizeItemName(String value) => value.trim();

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

/// 金额（分 → ¥xx.xx）。记录列表使用。
String formatMoney(int costCents) {
  return '¥${(costCents / 100).toStringAsFixed(2)}';
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

/// 紧凑里程文案：≥1万 显示"1.2万公里"。
String formatCompactMileageText(int value) {
  if (value >= 10000) {
    final wan = value / 10000;
    final text = wan == wan.roundToDouble()
        ? wan.toStringAsFixed(0)
        : wan.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return '$text万公里';
  }
  return '${formatNumber(value)}公里';
}

/// 紧凑时长文案：18 → "18个月"、24 → "2年"、30 → "2.5年"。
String formatCompactTimeText(int months) {
  if (months < 12) {
    return '$months个月';
  }
  if (months % 12 == 0) {
    return '${months ~/ 12}年';
  }
  final years = months / 12;
  final text = years.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$text年';
}

/// 里程维剩余文案（提醒详情用）。
String mileageReminderText(int remainingKm) {
  if (remainingKm > 0) {
    return '里程：距离下次约 ${formatNumber(remainingKm)} 公里';
  }
  if (remainingKm == 0) {
    return '里程：已到期';
  }
  return '里程：已超 ${formatNumber(remainingKm.abs())} 公里';
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

/// 统一错误翻译（≈ ExceptionHandler 的消息转换）：把 Repository 抛的
/// ArgumentError/StateError/SqliteException 文本映射为用户可读中文。
/// 全部表单的 catch 分支都走它；未匹配的异常兜底"操作失败，请稍后重试"
/// （⚠ 兜底会掩盖真实错误信息，调试时可先看日志再回来补映射）。
String friendlyError(Object error) {
  final message = error.toString();
  if (message.contains('这辆车当天')) {
    return message.replaceFirst('Bad state: ', '');
  }
  if (message.contains('UNIQUE constraint') ||
      message.contains('SqliteException(2067')) {
    return '这条数据已经保存过了';
  }
  if (message.contains('At least one maintenance item must stay enabled')) {
    return '至少保留一个可用保养项目';
  }
  if (message.contains('Maintenance item has history records')) {
    return '已有保养记录的项目不能删除';
  }
  if (message.contains('contains missing items')) {
    return '选择的保养项目不存在，请重新选择';
  }
  if (message.contains('items from another car')) {
    return '保养项目不属于当前车辆，请重新选择';
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

import 'package:flutter/material.dart';

import '../../../core/date/local_date.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_default_maintenance_item.dart';

InputDecoration numberInputDecoration({String? labelText, String? suffixText}) {
  return InputDecoration(labelText: labelText, suffixText: suffixText);
}

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

String formatPercent(int percent) {
  return percent > 999 ? '999%+' : '$percent%';
}

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

String normalizeItemName(String value) => value.trim();

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

List<String> recordItemNameList(
  MaintenanceRecord record,
  List<MaintenanceItem> items,
) {
  return record.itemIds
      .map((id) => itemById(items, id)?.name ?? '未知项目')
      .toList();
}

MaintenanceItem? itemById(List<MaintenanceItem> items, int itemId) {
  for (final item in items) {
    if (item.id == itemId) {
      return item;
    }
  }
  return null;
}

String formatMoney(int costCents) {
  return '¥${(costCents / 100).toStringAsFixed(2)}';
}

String formatMileageKm(int value) {
  return '${formatNumber(value)}km';
}

String formatCarAge(LocalDate roadDate, LocalDate today) {
  final months = roadDate.monthsUntil(today).clamp(0, 1200);
  final years = months / 12;
  final text = years.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$text年';
}

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

String mileageReminderText(int remainingKm) {
  if (remainingKm > 0) {
    return '里程：距离下次约 ${formatNumber(remainingKm)} 公里';
  }
  if (remainingKm == 0) {
    return '里程：已到期';
  }
  return '里程：已超 ${formatNumber(remainingKm.abs())} 公里';
}

String timeReminderText(int remainingDays) {
  if (remainingDays > 0) {
    return '时间：距离下次约 ${formatReminderDuration(remainingDays)}';
  }
  if (remainingDays == 0) {
    return '时间：今日到期';
  }
  return '时间：已超 ${formatReminderDuration(remainingDays.abs())}';
}

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

bool isUniqueConstraintError(Object error) {
  final message = error.toString();
  return message.contains('UNIQUE constraint') ||
      message.contains('SqliteException(2067)');
}

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

String formatDateForUser(LocalDate date) {
  return '${date.year}年${date.month}月${date.day}日';
}

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

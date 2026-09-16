// 桌面小组件快照组装层：当前应用车辆 + 提醒数据 → 快照 JSON（ADR 0013）。
//
// 在 App 中的位置：消费 reminder_rows.dart 的行组装单一出口，把"界面
// 看到的"算成一份只读快照交给桌面小组件渲染——小组件进程读不到数据库
// 与偏好，快照是它唯一的数据来源（CONTEXT.md"小组件快照"）。
// 消费方：widget_snapshot_controller.dart（同步编排）；本文件全部是
// 纯函数，不打通道、不碰 provider，可单测。
//
// 两个关键口径（拷问定稿 2026-09-16）：
//  - "今天"用调用方传入的有效今天（手动日期 ?? 系统今天），与提醒页
//    完全一致；小组件自己不做任何计算，连文案映射都在这里算好。
//  - 预生成窗口（CONTEXT.md"预生成窗口"）：按天把未来 N 天的展示
//    数据逐日重算成 entries，系统到点自动换页、App 不在也能翻页；
//    窗口外状态跨档等下次打开 App 重写快照。
// Java 类比：一个把领域对象投影成 JSON 报表的静态组装器（无状态的
// Converter），逐日条目 ≈ 预生成的定时报表快照。
import 'dart:convert';

import '../../../core/date/local_date.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import 'reminder_rows.dart';

/// 快照 JSON 契约版本（schemaVersion 字段）。改字段名/语义时 +1：
/// Swift 侧只认自己支持的版本，版本不符整体丢弃渲染占位（与备份
/// 契约同思路；测试直读本常量，不要手写魔法值）。
const int widgetSnapshotSchemaVersion = 1;

/// 预生成窗口天数：快照自带未来 N 天的逐日条目。窗口内状态跨档到点
/// 自动变色；跨档日落在窗口外就停在旧档，等下次打开 App 重写。
const int widgetSnapshotPregeneratedDays = 14;

/// 单个条目最多携带的项目行数（2026-09-16 原型拍板 M3+S2：小尺寸渲染
/// 4 行密集单行，中尺寸渲染前 3 行色块卡——各视图按自己的容量截断，
/// 快照统一带满 4 行）。选取沿用 buildReminderRows 的排序（状态越差越
/// 靠前→百分比降序→sortOrder），只截断、不再排序。
const int widgetSnapshotMaxRows = 4;

/// 组装桌面小组件快照 JSON。
///
/// 参数与 [buildReminderRows] 的四个上游一致（当前应用车辆可 null）。
/// 返回值经 `jsonEncode` 生成，结构（Swift 侧 LunioWidgetSnapshot 按此
/// 解码，缺字段解码失败按"无快照"渲染占位）：
/// ```json
/// {
///   "schemaVersion": 1,
///   "carName": "丰田 卡罗拉" | null,
///   "mileageKm": 32500 | null,
///   "emptyState": "noCar" | "noRecords" | "noItems" | null,
///   "entries": [
///     { "date": "yyyy-MM-dd", "overview": "超期 1 / 到期 2",
///       "items": [ { "name", "status", "badge", "percentText", "detail" } ] }
///   ]
/// }
/// ```
/// 空态时 entries 为空数组，小组件按 emptyState 渲染引导文案。
String buildWidgetSnapshotJson({
  required Car? car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final emptyState = car == null ? 'noCar' : _emptyStateKey(car: car, items: items, records: records, today: today);
  return jsonEncode(<String, Object?>{
    'schemaVersion': widgetSnapshotSchemaVersion,
    'carName': car == null ? null : '${car.brand} ${car.model}',
    'mileageKm': car?.currentMileageKm,
    'emptyState': emptyState,
    'entries': emptyState != null
        ? const <Object?>[]
        : <Object?>[
            for (var offset = 0; offset < widgetSnapshotPregeneratedDays; offset++)
              _dayEntry(
                car: car!,
                items: items,
                records: records,
                day: today.addDays(offset),
              ),
          ],
  });
}

/// 空态分类：复用 [classifyReminderRows] 的优先级（无记录 > 无启用
/// 项目 > 有数据）；无车（noCar）在调用方先行判断——车辆为 null 时
/// rows 必为空，走通用分类会误判成"无记录"。
String? _emptyStateKey({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final board = _boardFor(car: car, items: items, records: records, day: today);
  return switch (classifyReminderRows(board)) {
    ReminderRowsNoRecords() => 'noRecords',
    ReminderRowsNoEnabledItems() => 'noItems',
    ReminderRowsData() => null,
  };
}

/// 组装某一天的提醒看板（与 reminderRowsProvider 同一规则，只是"今天"
/// 换成预生成窗口内的第 N 天）。
ReminderRows _boardFor({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate day,
}) {
  return ReminderRows(
    noRecordsYet: records.isEmpty,
    rows: buildReminderRows(car: car, items: items, records: records, today: day),
  );
}

/// 单日条目：概览文案（复用英雄卡同一出口）+ 最紧急的前几行。
/// 调用方保证该日分类为有数据（空态时整段 entries 为空）。
Map<String, Object?> _dayEntry({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate day,
}) {
  final board = _boardFor(car: car, items: items, records: records, day: day);
  return <String, Object?>{
    'date': day.toString(),
    'overview': dueOverviewText(board),
    'items': <Object?>[
      for (final row in board.rows.take(widgetSnapshotMaxRows))
        <String, Object?>{
          'name': row.title,
          'status': row.progress.status.name,
          'badge': row.badge,
          'percentText': row.percentText,
          // 详情行按轴到期表达：时间到期说时间、里程到期说里程、
          // 都到期都说；都未到期回退里程优先的剩余行（与提醒页同源）。
          'detail': row.dueDetailText,
        },
    ],
  };
}

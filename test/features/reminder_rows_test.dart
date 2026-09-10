// reminder_rows.dart 的纯函数单测：行组装的排序规则、空态分类、
// 英雄卡"到期概览"文案分支。
// 不打 widget、不连数据库——直接构造实体。行组装逻辑此前只有 widget
// 测试间接覆盖，这是它的第一个直接测试面。

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/reminder.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/reminders/reminder_rows.dart';

final _sync = SyncMetadata(
  status: SyncStatus.synced,
  updatedAt: DateTime(2026, 1, 1),
);

Car _car() => Car(
  id: 1,
  brand: '丰田',
  model: '卡罗拉',
  currentMileageKm: 20000,
  roadDate: const LocalDate(2025, 1, 1),
  sync: _sync,
);

/// 只开时间维的保养项目（百分比 = 已用天数/间隔总天数×100，好算死）。
MaintenanceItem _timeItem({
  required int id,
  required String name,
  required int months,
  required int sortOrder,
  bool enabled = true,
}) => MaintenanceItem(
  id: id,
  carsId: 1,
  name: name,
  enabled: enabled,
  remindByMileage: false,
  remindByTime: true,
  timeIntervalMonths: months,
  sortOrder: sortOrder,
  sync: _sync,
);

MaintenanceRecord _record({required LocalDate date, required List<int> itemIds})
  => MaintenanceRecord(
    carId: 1,
    date: date,
    itemIds: itemIds,
    costCents: 0,
    mileageKm: 10000,
    sync: _sync,
  );

/// 直接构造展示模型（分类与概览文案测试用，不经过进度计算）。
ReminderViewData _row([ReminderStatus status = ReminderStatus.normal])
  => ReminderViewData(
    item: _timeItem(id: 1, name: '机油', months: 6, sortOrder: 0),
    progress: ReminderProgress(percent: 50, status: status),
    latestRecord: null,
  );

void main() {
  group('buildReminderRows 排序', () {
    test('状态越差越靠前，同状态百分比降序，停用项目不出现', () {
      // today=2026-09-10 下各场景百分比（时间维）：
      // 超期：134%（基线 2026-01-10，6 个月，已用 243/181 天）
      // 到期：109%（基线 2026-02-25，已用 197/181 天）
      // 正常高：92%（基线 2025-10-10，12 个月，已用 335/365 天）
      // 正常低：67%（基线 2026-01-10，12 个月，已用 243/365 天）
      final rows = buildReminderRows(
        car: _car(),
        items: [
          _timeItem(id: 1, name: '正常高', months: 12, sortOrder: 1),
          _timeItem(id: 2, name: '超期', months: 6, sortOrder: 2),
          _timeItem(id: 3, name: '正常低', months: 12, sortOrder: 3),
          _timeItem(id: 4, name: '到期', months: 6, sortOrder: 4),
          _timeItem(id: 5, name: '停用', months: 6, sortOrder: 0, enabled: false),
        ],
        records: [
          _record(date: const LocalDate(2025, 10, 10), itemIds: [1]),
          _record(date: const LocalDate(2026, 1, 10), itemIds: [2]),
          _record(date: const LocalDate(2026, 1, 10), itemIds: [3]),
          _record(date: const LocalDate(2026, 2, 25), itemIds: [4]),
        ],
        today: const LocalDate(2026, 9, 10),
      );
      expect(rows.map((row) => row.title).toList(), [
        '超期',
        '到期',
        '正常高',
        '正常低',
      ]);
      expect(rows.map((row) => row.progress.status).toList(), [
        ReminderStatus.danger,
        ReminderStatus.warning,
        ReminderStatus.normal,
        ReminderStatus.normal,
      ]);
    });

    test('同状态同百分比 → sortOrder 升序', () {
      final rows = buildReminderRows(
        car: _car(),
        items: [
          _timeItem(id: 1, name: '乙', months: 12, sortOrder: 20),
          _timeItem(id: 2, name: '甲', months: 12, sortOrder: 10),
        ],
        records: [
          _record(date: const LocalDate(2026, 1, 10), itemIds: [1, 2]),
        ],
        today: const LocalDate(2026, 9, 10),
      );
      expect(rows.map((row) => row.title).toList(), ['甲', '乙']);
    });
  });

  group('classifyReminderRows 空态分类', () {
    test('优先级：无记录 > 无启用项目 > 有数据', () {
      expect(
        classifyReminderRows(
          ReminderRows(noRecordsYet: true, rows: [_row()]),
        ),
        isA<ReminderRowsNoRecords>(),
      );
      expect(
        classifyReminderRows(
          const ReminderRows(noRecordsYet: false, rows: []),
        ),
        isA<ReminderRowsNoEnabledItems>(),
      );
      final ready = classifyReminderRows(
        ReminderRows(noRecordsYet: false, rows: [_row()]),
      );
      expect(ready, isA<ReminderRowsData>());
      expect((ready as ReminderRowsData).rows.length, 1);
    });
  });

  group('dueOverviewText 概览文案', () {
    String overview({
      required bool noRecords,
      required List<ReminderStatus> statuses,
    }) => dueOverviewText(
      ReminderRows(
        noRecordsYet: noRecords,
        rows: [for (final status in statuses) _row(status)],
      ),
    );

    test('空态走分类结果', () {
      expect(overview(noRecords: true, statuses: [ReminderStatus.normal]), '暂无');
      expect(overview(noRecords: false, statuses: const []), '无项目');
    });

    test('计数分支', () {
      expect(
        overview(
          noRecords: false,
          statuses: [
            ReminderStatus.danger,
            ReminderStatus.warning,
            ReminderStatus.warning,
            ReminderStatus.normal,
          ],
        ),
        '超期 1 / 到期 2',
      );
      expect(
        overview(noRecords: false, statuses: [ReminderStatus.danger]),
        '超期 1',
      );
      expect(
        overview(
          noRecords: false,
          statuses: [ReminderStatus.warning, ReminderStatus.warning],
        ),
        '到期 2',
      );
      expect(
        overview(
          noRecords: false,
          statuses: [ReminderStatus.normal, ReminderStatus.normal],
        ),
        '全部正常',
      );
    });
  });
}

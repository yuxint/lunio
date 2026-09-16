// widget_snapshot.dart 的纯函数单测：快照契约、空态分类、逐日预生成、
// top4 截断与排序。不打通道、不连数据库——直接构造实体（手法同
// record_rows_test.dart）。
//
// 变异验证锚点：跨档用例锁死"逐日重算"——若把预生成退化成"day0 算一
// 次复制 14 份"，窗口内的 状态/徽章 变化用例必死。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/reminders/widget_snapshot.dart';

final _sync = SyncMetadata(
  status: SyncStatus.synced,
  updatedAt: DateTime(2026, 1, 1),
);

const _today = LocalDate(2026, 9, 16);

Car _car() => Car(
  id: 1,
  brand: '丰田',
  model: '卡罗拉',
  currentMileageKm: 20000,
  roadDate: const LocalDate(2025, 1, 1),
  sync: _sync,
);

MaintenanceItem _item({
  required int id,
  required int timeIntervalMonths,
  double? notOverdueUpperLimit,
  double? overdueUpperLimit,
  bool enabled = true,
  bool remindByMileage = false,
  int? mileageIntervalKm,
}) => MaintenanceItem(
  id: id,
  carsId: 1,
  name: '项目$id',
  enabled: enabled,
  remindByMileage: remindByMileage,
  remindByTime: true,
  mileageIntervalKm: mileageIntervalKm,
  timeIntervalMonths: timeIntervalMonths,
  notOverdueUpperLimit: notOverdueUpperLimit ?? 100,
  overdueUpperLimit: overdueUpperLimit ?? 125,
  sortOrder: id,
  sync: _sync,
);

MaintenanceRecord _record({
  required LocalDate date,
  required List<int> itemIds,
}) => MaintenanceRecord(
  carId: 1,
  date: date,
  itemIds: itemIds,
  costCents: 0,
  mileageKm: 10000,
  sync: _sync,
);

Map<String, Object?> _decode(String json) => jsonDecode(json) as Map<String, Object?>;

void main() {
  group('契约与空态', () {
    test('无车：noCar 空态、无条目、车名/里程为 null', () {
      final json = _decode(
        buildWidgetSnapshotJson(
          car: null,
          items: const [],
          records: const [],
          today: _today,
        ),
      );
      expect(json['schemaVersion'], widgetSnapshotSchemaVersion);
      expect(json['carName'], isNull);
      expect(json['mileageKm'], isNull);
      expect(json['emptyState'], 'noCar');
      expect(json['entries'], isEmpty);
    });

    test('有车无记录：noRecords（优先于无项目）', () {
      final json = _decode(
        buildWidgetSnapshotJson(
          car: _car(),
          items: [_item(id: 1, timeIntervalMonths: 6)],
          records: const [],
          today: _today,
        ),
      );
      expect(json['emptyState'], 'noRecords');
      expect(json['entries'], isEmpty);
    });

    test('有记录但项目全停用：noItems', () {
      final json = _decode(
        buildWidgetSnapshotJson(
          car: _car(),
          items: [_item(id: 1, timeIntervalMonths: 6, enabled: false)],
          records: [_record(date: const LocalDate(2026, 3, 1), itemIds: [1])],
          today: _today,
        ),
      );
      expect(json['emptyState'], 'noItems');
      expect(json['entries'], isEmpty);
    });
  });

  group('数据态与逐日预生成', () {
    /// 单项目：2026-09-16 往前 24 天做过一次，1 个月间隔
    /// （基线 08-23 → 到期 09-23，总 31 天）。阈值覆写成 100/105，
    /// 让 warning（day+7 到期）→ danger（day+9 超 105%）两次跨档都
    /// 落进 14 天窗口——锁死"逐日重算"，杀死"day0 复制"变异。
    Map<String, Object?> buildSnapshot() {
      return _decode(
        buildWidgetSnapshotJson(
          car: _car(),
          items: [
            _item(
              id: 1,
              timeIntervalMonths: 1,
              notOverdueUpperLimit: 100,
              overdueUpperLimit: 105,
            ),
          ],
          records: [_record(date: const LocalDate(2026, 8, 23), itemIds: [1])],
          today: _today,
        ),
      );
    }

    test('条目数 = 预生成窗口，日期从今天起逐日 +1，车辆信息随带', () {
      final entries = buildSnapshot()['entries'] as List<Object?>;
      expect(buildSnapshot()['carName'], '丰田 卡罗拉');
      expect(buildSnapshot()['mileageKm'], 20000);
      expect(buildSnapshot()['emptyState'], isNull);
      expect(entries, hasLength(widgetSnapshotPregeneratedDays));
      for (var offset = 0; offset < entries.length; offset++) {
        final entry = entries[offset] as Map<String, Object?>;
        expect(entry['date'], _today.addDays(offset).toString());
      }
    });

    test('窗口内跨档：正常 → 到期(day+7) → 超期(day+9)，概览随行', () {
      final entries = buildSnapshot()['entries'] as List<Object?>;
      Map<String, Object?> day(int offset) =>
          entries[offset] as Map<String, Object?>;

      expect((day(0)['items'] as List).first as Map, parsesStatus('normal', '正常'));
      expect(day(0)['overview'], '全部正常');
      expect((day(7)['items'] as List).first as Map, parsesStatus('warning', '到期'));
      expect(day(7)['overview'], '到期 1');
      expect((day(9)['items'] as List).first as Map, parsesStatus('danger', '超期'));
      expect(day(9)['overview'], '超期 1');
    });

    test('行字段映射：名称/百分比/详情（都未到期回退里程优先）', () {
      final json = _decode(
        buildWidgetSnapshotJson(
          car: _car(),
          items: [
            _item(
              id: 1,
              timeIntervalMonths: 6,
              remindByMileage: true,
              // 已用 10000 / 间隔 20000 = 50%，里程维正常。
              mileageIntervalKm: 20000,
            ),
          ],
          records: [_record(date: const LocalDate(2026, 9, 1), itemIds: [1])],
          today: _today,
        ),
      );
      final item =
          ((json['entries'] as List).first as Map)['items'] as List<Object?>;
      final row = item.first as Map<String, Object?>;
      expect(row['name'], '项目1');
      expect(row['status'], 'normal');
      expect(row['badge'], '正常');
      expect(row['percentText'], '50%');
      // 两轴都没到期：回退里程行（与提醒页详情同序）。
      expect(row['detail'], startsWith('里程：'));
    });

    test('时间单轴到期：详情说时间，不再显示里程剩余（2026-09-16 反馈）', () {
      final json = _decode(
        buildWidgetSnapshotJson(
          car: _car(),
          items: [
            _item(
              id: 1,
              // 时间维：记录 2026-08-07 + 1 个月 = 09-07 到期，已超 9 天。
              timeIntervalMonths: 1,
              remindByMileage: true,
              // 里程维：已用 10000 / 间隔 20000，还剩 10000 公里，未到期。
              mileageIntervalKm: 20000,
            ),
          ],
          records: [_record(date: const LocalDate(2026, 8, 7), itemIds: [1])],
          today: _today,
        ),
      );
      final row =
          (((json['entries'] as List).first
                    as Map)['items'] as List<Object?>)
              .first as Map<String, Object?>;
      expect(row['status'], 'danger');
      expect(row['detail'], contains('时间：'));
      expect(row['detail'], contains('已超'));
      // 里程轴未到期，不得混进来误导（旧行为取第一行就是这个错）。
      expect(row['detail'], isNot(contains('里程：')));
    });

    test('两轴都到期：里程与时间都展示', () {
      final json = _decode(
        buildWidgetSnapshotJson(
          car: _car(),
          items: [
            _item(
              id: 1,
              timeIntervalMonths: 1,
              remindByMileage: true,
              // 里程维：已用 10000 / 间隔 5000，已超 5000 公里。
              mileageIntervalKm: 5000,
            ),
          ],
          records: [_record(date: const LocalDate(2026, 8, 7), itemIds: [1])],
          today: _today,
        ),
      );
      final row =
          (((json['entries'] as List).first
                    as Map)['items'] as List<Object?>)
              .first as Map<String, Object?>;
      expect(row['status'], 'danger');
      expect(row['detail'], contains('里程：已超'));
      expect(row['detail'], contains('时间：已超'));
      // 里程行在前（与提醒页详情同序），逗号连接。
      expect(row['detail'], startsWith('里程：'));
    });

    test('top4 截断：按状态→百分比→sortOrder 取前 4，概览按全量行计数', () {
      // 一条记录做全 5 项（63 天前）；间隔越短进度越靠前：
      // 项目1（1个月，超期红）> 项目2（2个月，到期黄）>
      // 项目3（3个月）> 项目4（6个月）> 项目5（12个月），全部正常绿。
      final json = _decode(
        buildWidgetSnapshotJson(
          car: _car(),
          items: [
            _item(id: 1, timeIntervalMonths: 1),
            _item(id: 2, timeIntervalMonths: 2),
            _item(id: 3, timeIntervalMonths: 3),
            _item(id: 4, timeIntervalMonths: 6),
            _item(id: 5, timeIntervalMonths: 12),
          ],
          records: [
            _record(date: const LocalDate(2026, 7, 15), itemIds: [1, 2, 3, 4, 5]),
          ],
          today: _today,
        ),
      );
      final entry = (json['entries'] as List).first as Map<String, Object?>;
      final items = entry['items'] as List<Object?>;
      expect(items, hasLength(widgetSnapshotMaxRows));
      expect(
        items.map((row) => (row as Map)['name']),
        ['项目1', '项目2', '项目3', '项目4'],
      );
      // 概览文案数全量 5 行，不是只数带出来的 4 行。
      expect(entry['overview'], '超期 1 / 到期 1');
    });
  });
}

/// 断言行 Map 的 status/badge 二元组（测试可读性小助手）。
Matcher parsesStatus(String status, String badge) {
  return isA<Map>().having((m) => m['status'], 'status', status)
      .having((m) => m['badge'], 'badge', badge);
}

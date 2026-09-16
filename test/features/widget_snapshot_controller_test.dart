// WidgetSnapshotController 的单元测试：快照写入的触发与守卫分支
// （ADR 0013）。数据上游直接用 provider 覆写（免数据库），原生桥用
// 假实现收调用——手法同 notification_sync_controller_test.dart 的宿主
// widget 模式。锁死：
//  - 数据就绪首拍恰好写一次，内容相同不重写（签名记账）；
//  - 上游还在 loading 时跳过，就绪那一拍补写（守卫删了会提前写空）；
//  - 数据变化触发重写；
//  - 写入失败（非 iOS 等）不记账，下个触发点重试；
//  - dispose 后 sync 直接放弃。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/core/platform/native_widgets.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/reminders/widget_snapshot_controller.dart';

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

MaintenanceItem _item() => MaintenanceItem(
  id: 1,
  carsId: 1,
  name: '机油',
  enabled: true,
  remindByMileage: false,
  remindByTime: true,
  timeIntervalMonths: 6,
  sortOrder: 1,
  sync: _sync,
);

MaintenanceRecord _record() => MaintenanceRecord(
  carId: 1,
  date: const LocalDate(2026, 8, 1),
  itemIds: const [1],
  costCents: 0,
  mileageKm: 10000,
  sync: _sync,
);

/// 测试本地数据源：模拟"记录数据变了"触发上游重算。
class _RecordsSeed extends Notifier<List<MaintenanceRecord>> {
  @override
  List<MaintenanceRecord> build() => const [];
  void set(List<MaintenanceRecord> value) => state = value;
}

final _recordsSeedProvider =
    NotifierProvider<_RecordsSeed, List<MaintenanceRecord>>(_RecordsSeed.new);

/// 测试本地数据源：模拟"保养项目变了"触发上游重算。
class _ItemsSeed extends Notifier<List<MaintenanceItem>> {
  @override
  List<MaintenanceItem> build() => [_item()];
  void set(List<MaintenanceItem> value) => state = value;
}

final _itemsSeedProvider =
    NotifierProvider<_ItemsSeed, List<MaintenanceItem>>(_ItemsSeed.new);

/// 测试本地数据源：模拟"今天变了"（手动日期 / 跨零点）触发上游重算。
class _TodaySeed extends Notifier<LocalDate> {
  @override
  LocalDate build() => const LocalDate(2026, 9, 16);
  void set(LocalDate value) => state = value;
}

final _todaySeedProvider =
    NotifierProvider<_TodaySeed, LocalDate>(_TodaySeed.new);

/// 假原生桥：收 JSON 调用；[deliver] 控制模拟送达成败。
class _FakeNativeWidgets implements NativeWidgets {
  final calls = <String>[];
  bool deliver = true;

  @override
  Future<bool> updateSnapshot(String json) async {
    calls.add(json);
    return deliver;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _FakeNativeWidgets fake;

  Future<WidgetSnapshotController> pumpHost(WidgetTester tester) async {
    final hostKey = GlobalKey<_ControllerHostState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _ControllerHost(key: hostKey),
      ),
    );
    return hostKey.currentState!.controller;
  }

  setUp(() {
    fake = _FakeNativeWidgets();
    container = ProviderContainer(
      overrides: [
        nativeWidgetsProvider.overrideWithValue(fake),
        appliedCarProvider.overrideWith((ref) async => _car()),
        appliedCarMaintenanceItemsProvider.overrideWith(
          (ref) async => ref.watch(_itemsSeedProvider),
        ),
        appliedCarRecordsProvider.overrideWith(
          (ref) async => ref.watch(_recordsSeedProvider),
        ),
        effectiveTodayProvider.overrideWith(
          (ref) async => ref.watch(_todaySeedProvider),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('快照同步触发（ADR 0013）', () {
    testWidgets('数据就绪首拍恰好写一次，内容相同不重写', (tester) async {
      final controller = await pumpHost(tester);
      await tester.pumpAndSettle();

      expect(fake.calls, hasLength(1));
      expect(fake.calls.first, contains('丰田 卡罗拉'));

      // 内容没变的手动触发不产生第二次写入。
      await controller.syncSnapshot();
      expect(fake.calls, hasLength(1));
    });

    testWidgets('数据变化触发重写，新内容带新数据', (tester) async {
      await pumpHost(tester);
      await tester.pumpAndSettle();
      // 无记录首拍：noRecords 空态、无条目。
      expect(fake.calls, hasLength(1));
      expect(fake.calls.first, contains('"emptyState":"noRecords"'));

      container.read(_recordsSeedProvider.notifier).set([_record()]);
      await tester.pumpAndSettle();

      // 有数据重写：带出项目行，空态清空。
      expect(fake.calls, hasLength(2));
      expect(fake.calls.last, contains('机油'));
      expect(fake.calls.last, contains('"emptyState":null'));
    });

    testWidgets('保养项目变化触发重写', (tester) async {
      await pumpHost(tester);
      await tester.pumpAndSettle();
      // 先播种记录，让快照进入数据态（含项目行）。
      container.read(_recordsSeedProvider.notifier).set([_record()]);
      await tester.pumpAndSettle();
      final before = fake.calls.length;

      // 新增一个保养项目 → 触发重写。
      container.read(_itemsSeedProvider.notifier).set([
        _item(),
        MaintenanceItem(
          id: 2,
          carsId: 1,
          name: '刹车油',
          enabled: true,
          remindByMileage: false,
          remindByTime: true,
          timeIntervalMonths: 24,
          sortOrder: 2,
          sync: _sync,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(fake.calls.length, greaterThan(before));
      expect(fake.calls.last, contains('刹车油'));
    });

    testWidgets('今天变化（手动日期/跨零点）触发重写', (tester) async {
      await pumpHost(tester);
      await tester.pumpAndSettle();
      // 播种记录进入数据态，首拍含 entries 且带日期。
      container.read(_recordsSeedProvider.notifier).set([_record()]);
      await tester.pumpAndSettle();
      expect(fake.calls.last, contains('2026-09-16'));

      // 改手动日期 → 触发重写，新快照带新日期。
      container
          .read(_todaySeedProvider.notifier)
          .set(const LocalDate(2026, 9, 20));
      await tester.pumpAndSettle();
      expect(fake.calls.last, contains('2026-09-20'));
    });

    testWidgets('写入失败不记账：下个触发点会重试', (tester) async {
      fake.deliver = false;
      final controller = await pumpHost(tester);
      await tester.pumpAndSettle();
      expect(fake.calls, hasLength(1));

      // 失败未缓存 → 同内容再触发仍会尝试写。
      await controller.syncSnapshot();
      expect(fake.calls, hasLength(2));
    });

    testWidgets('dispose 后 sync 直接放弃', (tester) async {
      final controller = await pumpHost(tester);
      await tester.pumpAndSettle();
      expect(fake.calls, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await controller.syncSnapshot();
      expect(fake.calls, hasLength(1));
    });
  });
}

/// 宿主 widget：真实构造 WidgetSnapshotController 并 start（生产由
/// AppShell 的 State 做），控制器随宿主卸载 dispose。
class _ControllerHost extends ConsumerStatefulWidget {
  const _ControllerHost({super.key});

  @override
  ConsumerState<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends ConsumerState<_ControllerHost> {
  late final WidgetSnapshotController controller;

  @override
  void initState() {
    super.initState();
    controller = WidgetSnapshotController(
      ref: ref,
      isAlive: () => mounted,
    )..start();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

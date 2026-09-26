// 两步表单状态机控制器（RecordFormController）的单元测试。
//
// 直接打控制器接口（不用 pump widget），锁死从 widget State 收编出来的
// 全部决策（2026-09-26，决策与循环驱动归控制器、弹窗实现归 widget）：
//  - 第一步校验：里程/费用/项目数，失败报行内错误、留在第一步；
//  - 步进：校验成功 → 里程单调软提示（新增编辑都查、未就绪跳过、编辑
//    排除自身）→「仍要继续」/无冲突进第二步，「返回修改」留第一步；
//  - 新增同日查重循环：打开即查、选完日期再查、有重复弹「返回/去编辑」
//    ——「返回」重开日期选择器选完再查（循环），「去编辑」经 exitToEdit
//    退出；编辑模式打开与选日期都不查；
//  - 第二步提交载荷：间隔没变不产生 update、非法值报行内错误、
//    SyncMetadata 用注入时钟；
//  - 行内新增项目承接：重拉列表 diff 自动勾选、费用草稿同步。
//
// UI 答案（日期选择器/两个确认框）脚本化注入，查重与软提示的分支都在
// 这里锁定；规则本体（conflictingMileageRecord）在 record_rules_test 覆盖。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/records/record_form_controller.dart';

MaintenanceItem makeItem(int id, String name, {bool enabled = true}) {
  return MaintenanceItem(
    id: id,
    carsId: 1,
    name: name,
    enabled: enabled,
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 5000,
    timeIntervalMonths: 6,
    sortOrder: 0,
    sync: SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026, 9, 1),
    ),
  );
}

final _car = Car(
  id: 1,
  brand: '本田',
  model: '思域（燃油版）',
  currentMileageKm: 12000,
  roadDate: const LocalDate(2026, 1, 1),
  sync: SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026)),
);

MaintenanceRecord makeRecord({
  int? id,
  required LocalDate date,
  required int mileageKm,
  List<int> itemIds = const [1],
}) {
  return MaintenanceRecord(
    id: id,
    carId: 1,
    date: date,
    itemIds: itemIds,
    itemCosts: const [],
    costCents: 0,
    mileageKm: mileageKm,
    sync: SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026)),
  );
}

/// UI 答案脚本与捕获（每个用例新建一份）：pickedDates/duplicateAnswers/
/// mileageAnswers 是脚本队列（按序消费，用尽再取会抛，天然暴露多余
/// 弹窗），exitToEditCalls/errors 是捕获列表；records 是可变记录快照桩。
class _Script {
  final pickedDates = <LocalDate?>[];
  final duplicateAnswers = <bool>[];
  final mileageAnswers = <bool>[];
  final exitToEditCalls = <MaintenanceRecord>[];
  final errors = <String?>[];
  int dateChangedCalls = 0;
  List<MaintenanceRecord>? records = const [];

  RecordFormController build({
    MaintenanceRecord? editRecord,
    List<MaintenanceItem>? items,
  }) {
    return RecordFormController(
      car: _car,
      items: items ?? [makeItem(1, '机油'), makeItem(2, '机滤')],
      initialDate: const LocalDate(2026, 5, 19),
      record: editRecord,
      ui: RecordFormUi(
        pickDate: (initial) async => pickedDates.removeAt(0),
        askDuplicate: (existing) async => duplicateAnswers.removeAt(0),
        askMileageProceed: (conflict) async => mileageAnswers.removeAt(0),
        exitToEdit: exitToEditCalls.add,
      ),
      readRecords: () => records,
      reportError: errors.add,
      onDateChanged: () => dateChangedCalls++,
      now: () => DateTime(2026, 9, 26, 10),
    );
  }

  bool get noDialogShown =>
      pickedDates.isEmpty &&
      duplicateAnswers.isEmpty &&
      mileageAnswers.isEmpty &&
      exitToEditCalls.isEmpty;
}

void main() {
  group('第一步校验与步进', () {
    test('校验失败：里程非法报错并留在第一步', () async {
      final script = _Script();
      final form = script.build()..toggleItem(1);
      form.mileageController.text = 'abc';

      await form.goToIntervalStep();

      expect(form.recordDraft, isNull);
      expect(script.errors.last, '保养里程必须是非负整数');
      expect(script.noDialogShown, isTrue);
    });

    test('校验失败：费用负数报错并留在第一步', () async {
      final script = _Script();
      final form = script.build()..toggleItem(1);
      form.totalController.text = '-1';

      await form.goToIntervalStep();

      expect(form.recordDraft, isNull);
      expect(script.errors.last, '费用必须是非负数字');
    });

    test('校验失败：未选项目报错并留在第一步', () async {
      final script = _Script();
      final form = script.build();

      await form.goToIntervalStep();

      expect(form.recordDraft, isNull);
      expect(script.errors.last, '至少选择一个保养项目');
    });

    test('无冲突直接进第二步：草稿字段与间隔草稿齐备', () async {
      final script = _Script();
      final form = script.build()
        ..toggleItem(1)
        ..toggleItem(2);
      form.mileageController.text = '15000';
      form.totalController.text = '280.5';
      form.noteController.text = '  常规保养  ';

      await form.goToIntervalStep();

      final draft = form.recordDraft!;
      expect(draft.carId, _car.id);
      expect(draft.date, const LocalDate(2026, 5, 19));
      expect(draft.mileageKm, 15000);
      expect(draft.costCents, 28050);
      expect(draft.note, '常规保养');
      expect(draft.itemIds, [1, 2]);
      // 新增模式：pendingCreate + 注入时钟。
      expect(draft.sync.status, SyncStatus.pendingCreate);
      expect(draft.sync.updatedAt, DateTime(2026, 9, 26, 10));
      expect(form.intervalDrafts.map((d) => d.item.id), [1, 2]);
      expect(script.errors.last, isNull);
      expect(script.noDialogShown, isTrue);
    });

    test('上一步：退回第一步并释放间隔草稿', () async {
      final script = _Script();
      final form = script.build()..toggleItem(1);
      await form.goToIntervalStep();
      expect(form.recordDraft, isNotNull);

      form.backToFirstStep();

      expect(form.recordDraft, isNull);
      expect(form.intervalDrafts, isEmpty);
    });

    test('记录快照未就绪（null）跳过软提示直接进第二步', () async {
      final script = _Script()..records = null;
      final form = script.build()..toggleItem(1);

      await form.goToIntervalStep();

      expect(form.recordDraft, isNotNull);
      expect(script.mileageAnswers, isEmpty);
    });
  });

  group('里程单调软提示', () {
    // 冲突场景：已有 05-25@10000（晚于草稿日期但里程更低），新增默认
    // 05-19@12000 必冲突；widget 侧同款场景见 records_test.dart。
    test('有冲突：「仍要继续」放行进第二步', () async {
      final script = _Script()
        ..records = [
          makeRecord(date: const LocalDate(2026, 5, 25), mileageKm: 10000),
        ];
      final form = script.build()..toggleItem(1);
      script.mileageAnswers.addAll([true]);

      await form.goToIntervalStep();

      expect(form.recordDraft, isNotNull);
      expect(script.mileageAnswers, isEmpty);
    });

    test('有冲突：「返回修改」留在第一步不写草稿', () async {
      final script = _Script()
        ..records = [
          makeRecord(date: const LocalDate(2026, 5, 25), mileageKm: 10000),
        ];
      final form = script.build()..toggleItem(1);
      script.mileageAnswers.addAll([false]);

      await form.goToIntervalStep();

      expect(form.recordDraft, isNull);
      expect(script.errors, isEmpty); // 软提示不是校验错误，不报行内文案
    });

    test('编辑排除自身：只把别的记录当参照', () async {
      // 编辑记录自带勾选集（itemIds [1]），无需再勾。
      final self = makeRecord(
        id: 100,
        date: const LocalDate(2026, 5, 25),
        mileageKm: 10000,
      );
      final script = _Script()
        ..records = [
          makeRecord(
            id: 99,
            date: const LocalDate(2026, 5, 10),
            mileageKm: 10000,
          ),
          self,
        ];
      final form = script.build(editRecord: self);

      // 里程 10000 持平（非降）不冲突，且 05-25 那条自己不参与比较。
      await form.goToIntervalStep();
      expect(form.recordDraft, isNotNull);
      expect(script.mileageAnswers, isEmpty);

      // 退回改里程为 9000：与 05-10@10000 构成"晚的记录里程反而更低"。
      form.backToFirstStep();
      form.mileageController.text = '9000';
      script.mileageAnswers.addAll([false]);
      await form.goToIntervalStep();
      expect(form.recordDraft, isNull);
      expect(script.mileageAnswers, isEmpty);
    });
  });

  group('新增同日查重循环', () {
    test('打开无重复：不弹任何窗', () async {
      final script = _Script();
      final form = script.build();

      await form.formOpened();

      expect(script.noDialogShown, isTrue);
      expect(form.recordDate, const LocalDate(2026, 5, 19));
    });

    test('打开有重复：「去编辑」经 exitToEdit 携带该记录退出', () async {
      final existing = makeRecord(
        date: const LocalDate(2026, 5, 19),
        mileageKm: 9000,
      );
      final script = _Script()..records = [existing];
      final form = script.build();
      script.duplicateAnswers.addAll([true]);

      await form.formOpened();

      expect(script.exitToEditCalls, [existing]);
      expect(script.pickedDates, isEmpty);
    });

    test('「返回」重开日期选择器：换到无重复日期后停住', () async {
      final existing = makeRecord(
        date: const LocalDate(2026, 5, 19),
        mileageKm: 9000,
      );
      final script = _Script()
        ..records = [existing]
        ..pickedDates.addAll([const LocalDate(2026, 5, 18)]);
      final form = script.build();
      script.duplicateAnswers.addAll([false]);

      await form.formOpened();

      expect(form.recordDate, const LocalDate(2026, 5, 18));
      expect(script.duplicateAnswers, isEmpty);
      expect(script.pickedDates, isEmpty);
      expect(script.exitToEditCalls, isEmpty);
    });

    test('循环多轮：换日再撞再「去编辑」退出', () async {
      final existing = makeRecord(
        date: const LocalDate(2026, 5, 19),
        mileageKm: 9000,
      );
      final script = _Script()
        ..records = [existing]
        ..pickedDates.addAll([const LocalDate(2026, 5, 18)]);
      final form = script.build();
      script.duplicateAnswers.addAll([false]);

      await form.formOpened();
      expect(form.recordDate, const LocalDate(2026, 5, 18));

      // 再选回重复日：立即再弹，「去编辑」退出。
      script.pickedDates.addAll([const LocalDate(2026, 5, 19)]);
      script.duplicateAnswers.addAll([true]);
      await form.pickRecordDate();

      expect(script.exitToEditCalls, [existing]);
      expect(form.recordDate, const LocalDate(2026, 5, 19));
    });

    test('编辑模式：打开与选日期都不查重', () async {
      final existing = makeRecord(
        date: const LocalDate(2026, 5, 19),
        mileageKm: 9000,
      );
      final script = _Script()..records = [existing];
      final form = script.build(
        editRecord: makeRecord(
          id: 100,
          date: const LocalDate(2026, 5, 25),
          mileageKm: 10000,
        ),
      );

      await form.formOpened();
      expect(script.noDialogShown, isTrue);

      // 编辑模式选到已有记录的日期也不弹——保存时 Repository 唯一校验兜底。
      script.pickedDates.addAll([const LocalDate(2026, 5, 19)]);
      await form.pickRecordDate();
      expect(form.recordDate, const LocalDate(2026, 5, 19));
      expect(script.duplicateAnswers, isEmpty);
      expect(script.exitToEditCalls, isEmpty);
    });

    test('记录快照未就绪（null）：打开不查重', () async {
      final script = _Script()..records = null;
      final form = script.build();

      await form.formOpened();

      expect(script.noDialogShown, isTrue);
    });

    test('换到无重复日期：落定即通知 onDateChanged 一次', () async {
      // 打开即撞重复（默认 05-19 已有记录）→「返回」→ 换 05-18。
      // 打开时的默认日期不通知，换日落定后通知一次（widget 侧语义：
      // 查重弹窗悬着时 tile 已显示新值）。
      final existing = makeRecord(
        date: const LocalDate(2026, 5, 19),
        mileageKm: 9000,
      );
      final script = _Script()
        ..records = [existing]
        ..pickedDates.addAll([const LocalDate(2026, 5, 18)]);
      final form = script.build();
      script.duplicateAnswers.addAll([false]);

      await form.formOpened();

      expect(script.dateChangedCalls, 1);
      expect(form.recordDate, const LocalDate(2026, 5, 18));
    });

    test('编辑模式换日也通知 onDateChanged', () async {
      final script = _Script();
      final form = script.build(
        editRecord: makeRecord(
          id: 100,
          date: const LocalDate(2026, 5, 25),
          mileageKm: 10000,
        ),
      );
      script.pickedDates.addAll([const LocalDate(2026, 5, 20)]);

      await form.pickRecordDate();

      expect(script.dateChangedCalls, 1);
      expect(form.recordDate, const LocalDate(2026, 5, 20));
    });

    test('取消选日期：不通知', () async {
      final script = _Script()..pickedDates.addAll([null]);
      final form = script.build();

      await form.pickRecordDate();

      expect(form.recordDate, const LocalDate(2026, 5, 19));
      expect(script.dateChangedCalls, 0);
    });
  });

  group('字段事件与行内新增承接', () {
    test('toggleItem：勾选集合与费用草稿同步', () {
      final script = _Script();
      final form = script.build();

      form.toggleItem(1);
      expect(form.costDrafts.containsKey(1), isTrue);

      form.toggleItem(1);
      expect(form.selectedItemIds, isEmpty);
      expect(form.costDrafts.containsKey(1), isFalse);
    });

    test('itemPoolRefreshed：新项目自动勾选并建费用草稿', () {
      final script = _Script();
      final form = script.build()..toggleItem(1);

      form.itemPoolRefreshed([
        makeItem(1, '机油'),
        makeItem(2, '机滤'),
        makeItem(3, '燃油宝'),
      ]);

      expect(form.formItems, hasLength(3));
      expect(form.selectedItemIds, {1, 3});
      expect(form.costDrafts.containsKey(3), isTrue);
    });

    test('itemPoolRefreshed：无新项目只刷新列表不勾选', () {
      final script = _Script();
      final form = script.build();

      form.itemPoolRefreshed([makeItem(1, '机油'), makeItem(2, '机滤')]);

      expect(form.selectedItemIds, isEmpty);
      expect(form.availableItems.map((item) => item.id), [1, 2]);
    });

    test('availableItems：编辑模式保留已禁用的已选项目', () {
      final script = _Script();
      final items = [makeItem(1, '机油'), makeItem(2, '机滤', enabled: false)];

      // 编辑：历史勾选含已禁用的机滤（id 2）——仍要展示可选。
      final editForm = script.build(
        editRecord: makeRecord(
          id: 100,
          date: const LocalDate(2026, 5, 25),
          mileageKm: 10000,
          itemIds: [2],
        ),
        items: items,
      );
      expect(editForm.availableItems.map((item) => item.id), [1, 2]);

      // 新增：禁用项目不出现。
      final newForm = script.build(items: items);
      expect(newForm.availableItems.map((item) => item.id), [1]);
    });
  });

  _intervalGroup();
}

/// 第二步提交载荷用例（独立函数避免 main 过长）。
void _intervalGroup() {
  test('间隔没变不产生 update；改了生成 pendingUpdate 实体', () async {
    final script = _Script()
      ..records = [
        makeRecord(date: const LocalDate(2026, 5, 25), mileageKm: 10000),
      ];
    final form = script.build()..toggleItem(1);
    script.mileageAnswers.addAll([true]); // 05-19@12000 vs 05-25@10000 冲突放行
    await form.goToIntervalStep();

    // 未改间隔：无 update。
    var payload = await form.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.updates, isEmpty);

    // 改里程间隔为 8000：生成一条 pendingUpdate。
    form.backToFirstStep();
    script.mileageAnswers.addAll([true]);
    await form.goToIntervalStep();
    form.intervalDrafts.single.mileageController.text = '8000';
    payload = await form.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.updates, hasLength(1));
    expect(payload.updates.single.mileageIntervalKm, 8000);
    expect(payload.updates.single.sync.status, SyncStatus.pendingUpdate);
    expect(payload.updates.single.sync.updatedAt, DateTime(2026, 9, 26, 10));
    expect(payload.draft.id, isNull);
  });

  test('间隔非法值报行内错误返回 null', () async {
    final script = _Script();
    final form = script.build()..toggleItem(1);
    await form.goToIntervalStep();
    form.intervalDrafts.single.mileageController.text = '0';

    final payload = await form.submitPayload();

    expect(payload, isNull);
    expect(script.errors.last, isNotNull);
  });

  test('仍在第一步时先推进不自动提交（历史行为）', () async {
    final script = _Script();
    final form = script.build()..toggleItem(1);

    final payload = await form.submitPayload();

    expect(payload, isNull);
    expect(form.recordDraft, isNotNull);
  });
}

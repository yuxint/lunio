// 保养记录两步表单的状态机控制器：新增/编辑记录从"填基础信息"到
// "确认提醒间隔"的全部决策与字段状态。
//
// 职责：
//   1. 第一步字段态：日期、里程/备注输入、勾选项目集合、可见项目列表；
//   2. 步进：第一步校验 + 记录草稿构建 → 里程单调软提示 → 第二步间隔
//      草稿（进/退第二步的草稿建/释放）；
//   3. 新增同日查重循环：打开时与每次选完日期后检查，有重复弹「返回/
//      去编辑」——「返回」驱动日期选择器重开、选完再查，循环到选出无
//      重复日期或「去编辑」退出；编辑模式不查；
//   4. 行内新增项目的结果承接：重拉列表 diff 出新项目自动勾选；
//   5. 提交载荷：间隔输入 → buildItemUpdates（record_interval_updates）
//      → (draft, updates)。
//
// 在 App 中的位置：只被 records_page.dart 的 MaintenanceRecordForm 使用。
// ≈ Java Web 里表单页抽出来的 BackingBean（同 AddCarWizardController /
// RecordCostFormController 先例）：持有输入控件状态与流转决策，widget
// 只做渲染并把事件转接进来；回调只改状态不触发重建，widget 在事件返回
// 后自行 setState。
//
// 与两道既有 seam 的边界（拷问定稿 2026-09-26）：
//   - ADR 0016 表单运行时：本类不持有 FormSheetHandle、不碰 pop/toast/
//     saving；行内错误经注入的 reportError 写 handle（生命周期守卫留在
//     widget 侧的注入闭包）；
//   - ADR 0007 动作层：本类只产出提交载荷，写库（saveMaintenanceRecord）
//     的接线留在入口函数。
// 弹窗与日期选择器的实现、文案、跳转编排都是 UI 决策，经 [RecordFormUi]
// 注入；已有记录快照经注入 getter 读取（控制器不依赖 ref）。
import 'package:flutter/material.dart';

import '../../../core/date/local_date.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/rules/record_rules.dart';
import 'record_cost_form_controller.dart';
import 'record_interval_updates.dart';

/// 两步表单的 UI 答案注入点：控制器驱动查重循环与软提示流程时需要用户
/// 交互的答案。实现与文案留在 widget 侧（弹窗/日期选择器/跳转编排都是
/// UI 决策，本类不碰 BuildContext）。
class RecordFormUi {
  const RecordFormUi({
    required this.pickDate,
    required this.askDuplicate,
    required this.askMileageProceed,
    required this.exitToEdit,
  });

  /// 弹日期选择器（[initial] = 当前选中日期），返回 null = 用户取消。
  final Future<LocalDate?> Function(LocalDate initial) pickDate;

  /// 同日查重确认框：返回 true = 「去编辑」；false = 「返回」换日期。
  final Future<bool> Function(MaintenanceRecord existing) askDuplicate;

  /// 里程单调软提示确认框：返回 true = 「仍要继续」；false = 「返回修改」。
  final Future<bool> Function(MaintenanceRecord conflict) askMileageProceed;

  /// 「去编辑」跳转：关新增 sheet、转编辑该记录（入口函数接线，要用
  /// 外层 context，本类与表单 widget 都不自己做）。
  final void Function(MaintenanceRecord existing) exitToEdit;
}

/// 保养记录两步表单控制器（职责与边界见文件头）。
///
/// 接口约定：事件方法（formOpened / pickRecordDate / goToIntervalStep /
/// submitPayload 等）只改状态与经 [RecordFormUi]/reportError 与外界交互，
/// 不触发重建——widget 在事件返回后自行 setState（唯一例外：
/// [onDateChanged] 日期落定即通知，保证查重循环中途 tile 也立刻反映）。
/// 渲染所需的派生状态经 availableItems / recordDraft / totalController
/// 等 getter 暴露。
class RecordFormController {
  RecordFormController({
    required this.car,
    required List<MaintenanceItem> items,
    required LocalDate initialDate,
    MaintenanceRecord? record,
    required this.ui,
    required this.readRecords,
    required this.reportError,
    this.onDateChanged,
    DateTime Function()? now,
  }) : record = record,
       _now = now ?? DateTime.now,
       recordDate = record?.date ?? initialDate,
       mileageController = TextEditingController(
         text: (record?.mileageKm ?? car.currentMileageKm).toString(),
       ),
       noteController = TextEditingController(text: record?.note ?? ''),
       selectedItemIds = {...?record?.itemIds},
       formItems = items,
       _costForm = RecordCostFormController(
         record: record,
         formItems: items,
         selectedItemIds: {...?record?.itemIds},
         // 编辑带项目费用的记录自动进入详细模式（ADR 0010）。
         detailMode: record?.itemCosts.isNotEmpty ?? false,
       );

  /// 所属车辆（草稿的 carId 与里程默认值取它）。
  final Car car;

  /// 编辑目标记录（null = 新增）。
  final MaintenanceRecord? record;

  /// UI 答案注入点（先例：AddCarWizardController.loadTemplate）：弹窗/
  /// 日期选择器的实现与文案、去编辑跳转都在 widget 侧。
  final RecordFormUi ui;

  /// 已有记录快照注入点：控制器在打开/选完日期/下一步三个时点各取一次；
  /// widget 传 `() => ref.read(appliedCarRecordsProvider).value`，null =
  /// 记录未就绪（查重与里程检查跳过）。
  final List<MaintenanceRecord>? Function() readRecords;

  /// 行内错误注入点：控制器把校验/间隔校验的错误文案写到 widget 侧的
  /// handle.setFormError（ADR 0016 错误统一在把手上显示）。
  final void Function(String? message) reportError;

  /// 日期落定通知：[recordDate] 写入新选日期后立即回调（新增查重循环与
  /// 编辑换日都走）。widget 注入带 mounted 守卫的 setState，让日期 tile
  /// 在查重弹窗还悬着时就显示刚选的值（对齐收编前"选完日期即 setState"
  /// 的行为）；循环/事件结束后的整体重建仍由 widget 事件返回处兜底。
  /// null = 不通知。
  final void Function()? onDateChanged;

  final DateTime Function() _now;

  /// 第一阶段选中的记录日期（新增默认 = 生效今天，编辑 = 原日期）。
  LocalDate recordDate;

  /// 第一步的里程 / 备注输入框。
  final TextEditingController mileageController;
  final TextEditingController noteController;

  /// 已勾选的项目 id。
  final Set<int> selectedItemIds;

  /// 表单当前可见的项目列表（行内新增后会刷新）。
  List<MaintenanceItem> formItems;

  /// 费用区控制器（ADR 0010 算链与手改标记的唯一实现）：内部实现细节，
  /// 渲染经 totalController / costDrafts 等转发读，输入经
  /// onTotalChanged 等转发写。
  final RecordCostFormController _costForm;

  /// 第二步的记录草稿（非 null 表示已进入第二步）。
  MaintenanceRecord? recordDraft;

  /// 第二步每个项目的间隔输入草稿（含各自的 controller）。
  final List<RecordIntervalDraft> intervalDrafts = [];

  bool get isEditing => record != null;

  // ---- 渲染转发（费用区内部实现不外露）----

  /// 第一步"费用"字段的输入框。
  TextEditingController get totalController => _costForm.totalController;

  /// 详细模式开关状态（开关的单一事实源在费用控制器里）。
  bool get detailMode => _costForm.detailMode;

  /// 总费用不一致展示状态（只在详细模式提示，判定在费用控制器）。
  bool get totalMismatch => _costForm.totalMismatch;

  /// 各项目的费用草稿表（key = 项目 id），第一步详细模式渲染费用行用。
  Map<int, RecordCostDraft> get costDrafts => _costForm.drafts;

  /// 单个项目费用的不一致展示状态（项目费用红字 + 行黄三角）。
  bool costItemMismatch(int itemId) => _costForm.itemMismatch(itemId);

  /// 第一步可选的项目：新增只列启用项；编辑把已选但已禁用的项目一并
  /// 展示（否则历史勾选无处显示）。
  List<MaintenanceItem> get availableItems => record == null
      ? formItems.where((item) => item.enabled).toList()
      : formItems
            .where(
              (item) => item.enabled || selectedItemIds.contains(item.id),
            )
            .toList();

  // ---- 事件：打开与日期 ----

  /// 表单打开（widget 首帧渲染后调用）：新增模式立即查重（默认日期=
  /// 生效今天）；编辑模式不查——改日期撞已有记录时由 Repository 同日
  /// 唯一校验在保存时报错。
  Future<void> formOpened() async {
    if (record == null) {
      await _checkDuplicateAndOfferEdit();
    }
  }

  /// 点"保养日期"：弹日期选择器；新增模式选完立即查重（编辑模式跳过）。
  /// 也是查重循环"返回换日期"的复用入口。
  Future<void> pickRecordDate() async {
    await _pickRecordDate();
  }

  /// 选日期（查重循环的内核）：取消不动；选中新日期后先通知
  /// [onDateChanged]（tile 立即反映），新增模式再查一轮。
  Future<void> _pickRecordDate() async {
    final picked = await ui.pickDate(recordDate);
    if (picked == null) {
      return;
    }
    recordDate = picked;
    onDateChanged?.call();
    if (!isEditing) {
      await _checkDuplicateAndOfferEdit();
    }
  }

  /// 新增模式的同日查重与处置：当前日期已有记录时弹「返回/去编辑」—
  /// 「去编辑」回调 exitToEdit（关新增 sheet 转编辑，由入口函数接线）；
  /// 「返回」重开日期选择器换日期，选完再查一轮，循环到选出无重复日期
  /// 或去编辑退出。拦截始终在第一步。
  Future<void> _checkDuplicateAndOfferEdit() async {
    final existing = _findRecordOn(recordDate);
    if (existing == null) {
      return;
    }
    final gotoEdit = await ui.askDuplicate(existing);
    if (gotoEdit) {
      ui.exitToEdit(existing);
      return;
    }
    await _pickRecordDate();
  }

  /// 查当前车辆在 [date] 是否已有保养记录（{carId, date} 唯一约束保证
  /// 最多一条）。记录快照未就绪时返回 null 跳过检查——保存时
  /// Repository 的同日唯一校验仍会兜底报错。
  MaintenanceRecord? _findRecordOn(LocalDate date) {
    final records = readRecords();
    if (records == null) {
      return null;
    }
    for (final record in records) {
      if (record.date == date) {
        return record;
      }
    }
    return null;
  }

  // ---- 事件：第一步字段 ----

  /// 勾选/取消一个项目（费用草稿表随勾选集合同步）。
  void toggleItem(int itemId) {
    if (selectedItemIds.contains(itemId)) {
      selectedItemIds.remove(itemId);
    } else {
      selectedItemIds.add(itemId);
    }
    _costForm.syncSelection(selectedItemIds, formItems);
  }

  /// 切换详细模式（ADR 0010：只改标记，切换不删除已填的项目费用）。
  void setDetailMode(bool value) {
    _costForm.detailMode = value;
  }

  /// 总费用输入（费用字段）：转发费用控制器（手改标记 + 算链）。
  void onTotalChanged() => _costForm.onTotalChanged();

  /// 材料/工时输入：转发费用控制器（跑算链）。
  void onSplitCostChanged() => _costForm.onSplitCostChanged();

  /// 项目费用输入：转发费用控制器（手改标记 + 算链）。
  void onItemCostChanged(int itemId) => _costForm.onItemCostChanged(itemId);

  /// 行内新增项目保存后的结果承接：重拉的完整项目列表进来，diff 出
  /// 新项目自动勾选（用户不用再找），费用草稿表同步。diff 以调用前的
  /// formItems 为基准，新增多个时勾第一个（与历史行为一致）。
  void itemPoolRefreshed(List<MaintenanceItem> refreshedItems) {
    final knownIds = formItems
        .map((item) => item.id)
        .whereType<int>()
        .toSet();
    MaintenanceItem? newItem;
    for (final item in refreshedItems) {
      final id = item.id;
      if (id != null && !knownIds.contains(id)) {
        newItem = item;
        break;
      }
    }
    formItems = refreshedItems;
    if (newItem?.id != null) {
      selectedItemIds.add(newItem!.id!);
    }
    _costForm.syncSelection(selectedItemIds, formItems);
  }

  // ---- 事件：步进与提交 ----

  /// 第一步「下一步」：校验 + 构建记录草稿（失败报行内错误、留在第一
  /// 步）→ 里程单调软提示（新增与编辑都查，记录快照未就绪跳过，保存时
  /// Repository 既有校验兜底）——有冲突弹确认框，「仍要继续」放行进第
  /// 二步，「返回修改」留在第一步；无冲突直接进第二步。软提示两分支都
  /// 不写库。
  Future<void> goToIntervalStep() async {
    final draft = _buildRecordDraft();
    if (draft == null) {
      return;
    }
    final conflict = _findMileageConflict(draft);
    if (conflict != null) {
      final proceed = await ui.askMileageProceed(conflict);
      if (!proceed) {
        return;
      }
    }
    _enterIntervalStep(draft);
  }

  /// 第二步「上一步」：释放间隔草稿、退回第一步。
  void backToFirstStep() {
    _disposeIntervalDrafts();
    recordDraft = null;
    reportError(null);
  }

  /// 第二步「保存记录」的提交载荷：间隔输入 → buildItemUpdates（校验 +
  /// 生成 update 清单，正整数规则在 MaintenanceRules）→ 返回
  /// (draft, updates)。校验失败报行内错误返回 null；仍在第一步时先尝试
  /// 推进一步、不自动提交（历史行为）。写库由 widget 经 handle.submit →
  /// 动作层完成，本类不碰。
  Future<({MaintenanceRecord draft, List<MaintenanceItem> updates})?>
  submitPayload() async {
    final draft = recordDraft;
    if (draft == null) {
      await goToIntervalStep();
      return null;
    }
    final result = buildItemUpdates(drafts: intervalDrafts, now: _now());
    if (result.errorText != null) {
      reportError(result.errorText!);
      return null;
    }
    return (draft: draft, updates: result.updates);
  }

  /// 构造第二步的间隔输入草稿并切换视图（软提示「仍要继续」与无冲突
  /// 的共用出口）。
  void _enterIntervalStep(MaintenanceRecord draft) {
    final selectedItems = formItems
        .where((item) => item.id != null && selectedItemIds.contains(item.id))
        .toList();
    if (selectedItems.isEmpty) {
      reportError('至少选择一个保养项目');
      return;
    }
    _disposeIntervalDrafts();
    intervalDrafts.addAll(
      selectedItems.map((item) => RecordIntervalDraft(item: item)),
    );
    recordDraft = draft;
    reportError(null);
  }

  /// 第一步校验 + 构造记录草稿：里程非负整数、费用非负数字、至少选一
  /// 个项目。费用元→分四舍五入。失败返回 null 并报行内错误文案。项目
  /// 费用清单由费用控制器生成（全空草稿跳过；不一致是合法数据不校验，
  /// ADR 0010）。
  MaintenanceRecord? _buildRecordDraft() {
    final mileage = int.tryParse(mileageController.text);
    final cost = double.tryParse(_costForm.totalController.text);
    if (mileage == null || mileage < 0) {
      reportError('保养里程必须是非负整数');
      return null;
    }
    if (cost == null || cost < 0) {
      reportError('费用必须是非负数字');
      return null;
    }
    if (selectedItemIds.isEmpty) {
      reportError('至少选择一个保养项目');
      return null;
    }

    return MaintenanceRecord(
      id: record?.id,
      carId: car.id!,
      date: recordDate,
      itemIds: selectedItemIds.toList(),
      itemCosts: _costForm.buildItemCosts(),
      costCents: (cost * 100).round(),
      mileageKm: mileage,
      note: noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim(),
      sync: SyncMetadata(
        status: isEditing ? SyncStatus.pendingUpdate : SyncStatus.pendingCreate,
        updatedAt: _now(),
      ),
    );
  }

  /// 里程单调性软提示检查（第一步「下一步」时调用）：草稿与该车已有
  /// 记录构成"里程不随日期单调非降"时返回冲突参照记录。记录快照未就绪
  /// 时返回 null 跳过；编辑模式经草稿自身 id 排除自己（规则本体在
  /// RecordRules.conflictingMileageRecord）。
  MaintenanceRecord? _findMileageConflict(MaintenanceRecord draft) {
    final records = readRecords();
    if (records == null) {
      return null;
    }
    return RecordRules.conflictingMileageRecord(
      records: records,
      draftDate: draft.date,
      draftMileageKm: draft.mileageKm,
      selfRecordId: draft.id,
    );
  }

  /// 释放第二步所有间隔草稿的 controller。
  void _disposeIntervalDrafts() {
    for (final draft in intervalDrafts) {
      draft.dispose();
    }
    intervalDrafts.clear();
  }

  /// 释放全部输入控件（widget dispose 时调用）。
  void dispose() {
    _disposeIntervalDrafts();
    _costForm.dispose();
    mileageController.dispose();
    noteController.dispose();
  }
}

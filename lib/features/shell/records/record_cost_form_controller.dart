// 记录表单费用区的控制器：ADR 0010 自动算链与手改标记的唯一实现。
//
// 职责：管理详细模式下"材料费/工时费/项目费用/总费用"输入的草稿与联动——
//   1. 自动算链：材料>0 且工时>0 → 项目费用 = 两者之和（已手改的不覆盖）；
//      有项目费用 → 总费用 = 合计（已手改的不覆盖）。只在详细模式生效；
//   2. 手改标记：键入非空内容 = 手改（不再被自动覆盖）；清空 = 放弃手改
//      （恢复自动跟随）；编辑历史记录打开时，存量费用与自动算结果不一致
//      （如优惠改价）直接视为已手改，预填值不会被算链冲掉；
//   3. 不一致展示状态：项目费用 ≠ 材料+工时、总费用 ≠ 合计（红字黄三角，
//      纯提示不拦截保存，算术判定复用 RecordRules）；
//   4. 草稿生命周期：跟随勾选集合建/退草稿（含 controller 的释放），
//      编辑记录时从历史费用预填；
//   5. 提交清单生成：全空草稿跳过，元→分四舍五入，不一致不做校验
//      （合法数据，见 ADR 0010）。
//
// 在 App 中的位置：只被 records_page.dart 的两步表单第一步使用；
// 求和与不一致的算术在 domain/rules/record_rules.dart，本类只管输入态。
// ≈ Java Web 里表单页抽出来的 BackingBean：持有输入控件的状态与联动
// 规则，widget 只做渲染并把回调转接进来（重建 setState 留在调用方）。
//
// 手改保护的关键机制：程序写入 controller 文本会同步触发 TextField 的
// onChanged 递归回调，_applyingAutoFill 置位期间既不重入算链、也不把
// 程序写入记成手改——"自动回填不算用户手改"是语义的一部分，不是防抖。
import 'package:flutter/material.dart';

import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/rules/record_rules.dart';
import '../shared/formatters.dart';

/// 详细模式下单个项目的费用输入草稿：材料/工时/项目费用三个 controller
/// + 项目费用手改标记。编辑记录时从历史费用预填，金额文本与费用输入框
/// 同格式（两位小数）。
class RecordCostDraft {
  RecordCostDraft({required this.item, this.initial})
    : materialController = TextEditingController(
        text: initial?.materialCents == null
            ? ''
            : formatMoneyText(initial!.materialCents!),
      ),
      laborController = TextEditingController(
        text: initial?.laborCents == null
            ? ''
            : formatMoneyText(initial!.laborCents!),
      ),
      costController = TextEditingController(
        text: initial?.costCents == null
            ? ''
            : formatMoneyText(initial!.costCents!),
      ) {
    // 存量项目费用与"材料+工时"不一致（如优惠改价）说明是手改值：
    // 打开即视为手改，避免编辑材料/工时时被自动算链冲掉。与总费用的
    // totalTouched 预置同一策略（ADR 0010：手改后不再被自动覆盖）；
    // 一致的存量值（可能只是上次自动算的结果）仍保持自动跟随。
    final initialCost = initial;
    costTouched = initialCost != null &&
        RecordRules.itemCostMismatch(initialCost);
  }

  final MaintenanceItem item;
  final RecordItemCost? initial;
  final TextEditingController materialController;
  final TextEditingController laborController;
  final TextEditingController costController;

  /// 项目费用是否被手动改过（改过后不再被"材料+工时"自动覆盖；
  /// 清空视为放弃手改，恢复自动计算）。编辑记录打开时，存量项目费用
  /// 与"材料+工时"不一致（优惠价）即预置为已手改（见构造函数）。
  bool costTouched = false;

  void dispose() {
    materialController.dispose();
    laborController.dispose();
    costController.dispose();
  }
}

/// 记录表单费用区控制器（职责与手改语义见文件头）。
///
/// 接口约定：输入回调（onXxxChanged）内部只更新草稿文本与标记，不触发
/// 重建——调用方（表单 State）在回调返回后自行 setState 让不一致状态
/// 重渲染。总费用输入框（[totalController]）是第一步始终可见的"费用"
/// 字段：简洁模式下纯手填，详细模式下参与算链。
class RecordCostFormController {
  RecordCostFormController({
    MaintenanceRecord? record,
    required List<MaintenanceItem> formItems,
    required Set<int> selectedItemIds,
    this.detailMode = false,
  })  : _record = record,
        totalController = TextEditingController(
          text: record == null
              ? '0'
              : (record.costCents / 100).toStringAsFixed(2),
        ) {
    // 编辑历史不一致记录（如优惠让总费用低于合计）：打开即视为手改，
    // 避免自动合计冲掉用户存的数。与单项目草稿的预置同一策略。
    totalTouched = record != null &&
        record.costCents != RecordRules.sumItemCostCents(record.itemCosts);
    _syncDrafts(selectedItemIds, formItems);
  }

  /// 总费用输入框（第一步的"费用"字段）。
  final TextEditingController totalController;

  /// 构造时传入的编辑目标记录（null = 新增）。草稿预填历史费用取它。
  final MaintenanceRecord? _record;

  /// 是否详细模式（ADR 0010，默认简洁；编辑带项目费用的记录自动进入）。
  /// 单一事实源在这里：表单的开关与费用行渲染都读它。切换只改标记、
  /// 不立刻跑算链（下次输入生效），与历史行为一致。
  bool detailMode;

  /// 总费用是否被手动改过（改过后不再被项目费用合计自动覆盖；清空
  /// 视为放弃手改、恢复自动跟随）。
  bool totalTouched = false;

  final _drafts = <int, RecordCostDraft>{};

  /// 当前草稿表（key = 项目 id）。只读用途：表单据此渲染费用行。
  /// 草稿只存在于勾选集中的项目——勾选同步是 [syncSelection] 的职责。
  Map<int, RecordCostDraft> get drafts => _drafts;

  /// 自动算链的递归保护（语义见文件头）。
  bool _applyingAutoFill = false;

  /// 勾选集合变化后的草稿同步：取消勾选的草稿销毁（其费用从本次提交
  /// 里消失），新勾选的建草稿并预填该记录的历史费用。勾选变化和行内
  /// 新增项目刷新后都要调用。
  void syncSelection(
    Set<int> selectedItemIds,
    List<MaintenanceItem> formItems,
  ) {
    _syncDrafts(selectedItemIds, formItems);
  }

  /// 项目费用输入回调：维护该项目的手改标记（清空 = 放弃手改）→
  /// 跑自动算链。
  void onItemCostChanged(int itemId) {
    if (!_applyingAutoFill) {
      final draft = _drafts[itemId];
      if (draft != null) {
        draft.costTouched = draft.costController.text.trim().isNotEmpty;
      }
    }
    _applyAutoFill();
  }

  /// 材料费/工时费输入回调：跑自动算链（不涉及手改标记）。
  void onSplitCostChanged() {
    _applyAutoFill();
  }

  /// 总费用输入回调：键入内容视为手改（不再自动跟随合计），清空视为
  /// 放弃手改（下次合计变化会重新填入）。
  void onTotalChanged() {
    if (!_applyingAutoFill) {
      totalTouched = totalController.text.trim().isNotEmpty;
    }
    _applyAutoFill();
  }

  /// 单个项目费用的不一致展示状态（项目费用红字 + 行黄三角）。
  bool itemMismatch(int itemId) {
    final draft = _drafts[itemId];
    return draft != null &&
        RecordRules.itemCostMismatch(_draftToCost(draft));
  }

  /// 总费用的不一致展示状态。只在详细模式提示：简洁模式看不到项目
  /// 费用，单独把总费用标红只会让人困惑（ADR 0010）。
  bool get totalMismatch {
    if (!detailMode) {
      return false;
    }
    return RecordRules.totalCostMismatch(
      totalCostCents: parseMoneyCents(totalController.text) ?? 0,
      itemCosts: _currentItemCosts,
    );
  }

  /// 提交用的项目费用列表（ADR 0010）：草稿只存在于勾选集中（勾选
  /// 同步的不变量），三个金额全空的草稿跳过；金额元→分四舍五入，
  /// 空/非法 = 未填。不一致（项目费用 ≠ 材料+工时、总费用 ≠ 合计）
  /// 在这里不做校验——按产品规则不一致是合法数据（如优惠），由界面
  /// 红字黄三角提示。
  List<RecordItemCost> buildItemCosts() {
    final costs = <RecordItemCost>[];
    for (final draft in _drafts.values) {
      final itemId = draft.item.id;
      if (itemId == null) {
        continue;
      }
      final material = parseMoneyCents(draft.materialController.text);
      final labor = parseMoneyCents(draft.laborController.text);
      final cost = parseMoneyCents(draft.costController.text);
      if (material == null && labor == null && cost == null) {
        continue;
      }
      costs.add(
        RecordItemCost(
          itemId: itemId,
          materialCents: material,
          laborCents: labor,
          costCents: cost,
        ),
      );
    }
    return costs;
  }

  /// 释放全部草稿与总费用输入框。
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    _drafts.clear();
    totalController.dispose();
  }

  /// 把草稿表同步到当前勾选的项目集合（原表单 State 的 _syncCostDrafts）。
  void _syncDrafts(
    Set<int> selectedItemIds,
    List<MaintenanceItem> formItems,
  ) {
    _drafts.removeWhere((itemId, draft) {
      if (selectedItemIds.contains(itemId)) {
        return false;
      }
      draft.dispose();
      return true;
    });
    for (final item in formItems) {
      final itemId = item.id;
      if (itemId == null ||
          !selectedItemIds.contains(itemId) ||
          _drafts.containsKey(itemId)) {
        continue;
      }
      RecordItemCost? initial;
      for (final cost in _record?.itemCosts ?? const <RecordItemCost>[]) {
        if (cost.itemId == itemId) {
          initial = cost;
          break;
        }
      }
      _drafts[itemId] = RecordCostDraft(item: item, initial: initial);
    }
  }

  /// 自动算链（ADR 0010）：材料>0 且工时>0 → 项目费用 = 两者之和
  /// （已被手改的不覆盖）；有项目费用 → 总费用 = 合计（已被手改的
  /// 不覆盖）。只在详细模式生效，简洁模式总费用纯手填。
  void _applyAutoFill() {
    if (_applyingAutoFill) {
      return;
    }
    _applyingAutoFill = true;
    try {
      if (!detailMode) {
        return;
      }
      for (final draft in _drafts.values) {
        final material = parseMoneyCents(draft.materialController.text);
        final labor = parseMoneyCents(draft.laborController.text);
        if (material != null &&
            material > 0 &&
            labor != null &&
            labor > 0 &&
            !draft.costTouched) {
          final text = formatMoneyText(material + labor);
          if (draft.costController.text != text) {
            draft.costController.text = text;
          }
        }
      }
      final sum = RecordRules.sumItemCostCents(_currentItemCosts);
      if (sum > 0 && !totalTouched) {
        final text = formatMoneyText(sum);
        if (totalController.text != text) {
          totalController.text = text;
        }
      }
    } finally {
      _applyingAutoFill = false;
    }
  }

  /// 当前输入态的项目费用列表（金额从文本解析，空/非法 = 未填）。
  /// 供合计与不一致判定使用。
  List<RecordItemCost> get _currentItemCosts {
    return [
      for (final draft in _drafts.values) _draftToCost(draft),
    ];
  }

  /// 单个草稿 → 输入态项目费用（金额从文本解析，空/非法 = 未填）。
  RecordItemCost _draftToCost(RecordCostDraft draft) {
    return RecordItemCost(
      itemId: draft.item.id ?? 0,
      materialCents: parseMoneyCents(draft.materialController.text),
      laborCents: parseMoneyCents(draft.laborController.text),
      costCents: parseMoneyCents(draft.costController.text),
    );
  }
}

// 加油页（/fuel）：加油预测的交互页面。
//
// 页面结构：
//   1. 油价卡：当前省+油品的每升价（手填价 > 数据源价），带刷新/手填/清除；
//      副标题"湖北 · 92#"的省份、油品两段各自可点弹出选择 sheet
//      （设置很少改，不再单设设置区）；省份 31 项用列表 sheet 内部限高
//      滚动，油品固定 4 项用一行胶囊单选（sheet 贴内容，很矮）；
//   2. 加满预估卡：全量档位列表（100%→0%，2% 一档共 51 档），窗口内
//      可见 5 档，可上下滚动；滚动停稳后第一行所在的档位就是剩余油量
//      （自动写库，下次进入定位到该档在第一行）；右上角返回图标滚回
//      默认 50%。油箱容积在"我的 → 车辆管理"添加/编辑车辆时填写
//      （选填），没填时本卡显示引导。
//   无应用车辆时整页占位提示"请先新增车辆"。
//
// 数据规则（设计决定见 CONTEXT.md / ADR 0001 / ADR 0002）：
//   - 剩余油量按车存 fuel_predictions 表（默认 50%，滚动定档才落库）；
//     省份、油品全局存偏好；油箱容积 v8 起在 cars 表（车的属性）；
//   - 油价来源优先级：手填价 > 数据源价；手填不被自动/手动刷新覆盖；
//   - 所有修改即写库（自动保存），无保存按钮。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../data/fuel/mock_fuel_price_source.dart';
import '../../../data/repositories/lunio_repository.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/fuel_prediction.dart';
import '../../../domain/entities/fuel_price.dart';
import '../../../domain/rules/fuel_rules.dart';
import '../shared/formatters.dart';
import '../shared/modal_feedback.dart';
import '../shared/shared_widgets.dart';

/// 加油页入口（AppShell 底部导航，仅"加油预测"开关打开时显示）。
class FuelPreviewPage extends ConsumerWidget {
  const FuelPreviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final car = ref
        .watch(appliedCarProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    return LunioPage(
      title: '加油',
      children: [
        if (car == null)
          const LunioCard(child: Text('请先新增车辆'))
        else
          _FuelContent(car: car),
      ],
    );
  }
}

class _FuelContent extends ConsumerWidget {
  const _FuelContent({required this.car});

  final Car car;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 加载中与"从没保存过"要区分开：档位列表首次定位依赖已存档位，
    // 没存过按默认 50% 定位；loading 期间先不渲染列表，避免先按 50%
    // 定位又跳到已存档位的视觉跳动。
    final predictionAsync = ref.watch(appliedCarFuelPredictionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PriceCard(),
        const SizedBox(height: 12),
        predictionAsync.when(
          skipLoadingOnReload: true,
          loading: () => const LunioCard(child: Text('读取中')),
          error: (error, stackTrace) => _TierListCard(
            carId: car.id!,
            capacity: car.tankCapacityLiters,
            savedPercent: null,
          ),
          data: (prediction) => _TierListCard(
            carId: car.id!,
            capacity: car.tankCapacityLiters,
            savedPercent: prediction?.fuelPercent,
          ),
        ),
      ],
    );
  }
}

// ---------------- 油价卡（省份/油品编辑入口也在这里） ----------------

class _PriceCard extends ConsumerWidget {
  const _PriceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final province = ref
        .watch(fuelProvinceProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final grade = ref
        .watch(fuelGradeProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final priceState = ref.watch(fuelPriceControllerProvider);
    final manualPrice = ref
        .watch(fuelManualPriceProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);

    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '当前油价',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SmallActionButton(
                label: '手填',
                onPressed: province == null || grade == null
                    ? null
                    : () => _editManualPrice(context, ref),
              ),
              const SizedBox(width: 8),
              SmallActionButton(
                label: '刷新',
                onPressed: priceState.isLoading
                    ? null
                    : () => _manualRefresh(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildPriceBody(
            context,
            ref,
            province,
            grade,
            priceState,
            manualPrice,
          ),
        ],
      ),
    );
  }

  /// 油价展示：手填价优先；其次数据源价；都没有时给"暂无数据"引导。
  /// 副标题"省份 · 油品"两段各自可点，点开对应的选择 sheet。
  Widget _buildPriceBody(
    BuildContext context,
    WidgetRef ref,
    String? province,
    FuelGrade? grade,
    AsyncValue<FuelPriceData?> priceState,
    double? manualPrice,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    if (province == null || grade == null) {
      return const Text('设置读取中');
    }
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: tokens.muted,
    );
    Widget priceLine;
    if (manualPrice != null) {
      priceLine = _priceRow(
        context,
        '${manualPrice.toStringAsFixed(2)} 元/升',
        '手填价',
        tokens.primary,
      );
    } else {
      final data = priceState.maybeWhen(
        data: (value) => value,
        orElse: () => null,
      );
      if (priceState.isLoading && data == null) {
        priceLine = Text('油价获取中…', style: subtitleStyle);
      } else if (data == null) {
        priceLine = Text('暂无油价数据，可稍后刷新或手填。', style: subtitleStyle);
      } else {
        final price = data.priceFor(grade);
        if (price == null) {
          priceLine = Text('该油品暂无价格，可手填。', style: subtitleStyle);
        } else {
          final updatedText =
              '${data.fetchedAt.month}月${data.fetchedAt.day}日更新';
          priceLine = _priceRow(
            context,
            '${price.toStringAsFixed(2)} 元/升',
            updatedText,
            tokens.ink,
          );
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SettingHotspot(
              label: province,
              onTap: () => _pickProvince(context, ref, province),
            ),
            Text(' · ', style: subtitleStyle),
            _SettingHotspot(
              label: grade.label,
              onTap: () => _pickGrade(context, ref, grade),
            ),
          ],
        ),
        const SizedBox(height: 6),
        priceLine,
      ],
    );
  }

  Widget _priceRow(
    BuildContext context,
    String priceText,
    String tagText,
    Color priceColor,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          priceText,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: priceColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: tokens.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tokens.line),
          ),
          child: Text(
            tagText,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Spacer(),
        SmallActionButton(
          label: '清除',
          danger: true,
          onPressed: () => _clearManualPrice(context),
        ),
      ],
    );
  }

  /// 选省份：写偏好 → 失效省份/油价相关 provider（油价控制器会因换省
  /// 自动重新拉取）。列表 31 项较长，sheet 内容区限高滚动，
  /// 打开时定位到当前省份所在行。
  Future<void> _pickProvince(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    await showLunioModalSheet<void>(
      context: context,
      builder: (sheetContext) {
        final initialIndex = MockFuelPriceSource.provinces.indexOf(current);
        return PrototypeSheetFrame(
          title: '选择省份',
          child: _SheetOptionList(
            labels: MockFuelPriceSource.provinces,
            selectedIndex: initialIndex,
            onSelected: (name) async {
              await ref
                  .read(lunioRepositoryProvider)
                  .setPreferenceValue(
                    LunioRepository.fuelProvincePreferenceKey,
                    name,
                  );
              invalidateFuelPreferenceProviders(ref);
            },
          ),
        );
      },
    );
  }

  /// 选油品：固定 4 项（92/95/98/0#），用一行胶囊单选，点选即写偏好 →
  /// 失效油品/手填价 provider 并关 sheet。选项少，不走省份那种竖排
  /// 列表（用户反馈列表 sheet 下方留白，改为贴内容的胶囊后 sheet 很矮）。
  Future<void> _pickGrade(
    BuildContext context,
    WidgetRef ref,
    FuelGrade current,
  ) async {
    await showLunioModalSheet<void>(
      context: context,
      builder: (sheetContext) {
        return PrototypeSheetFrame(
          title: '选择油品',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final grade in FuelGrade.values)
                _GradeChip(
                  label: grade.label,
                  selected: grade == current,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await ref
                        .read(lunioRepositoryProvider)
                        .setPreferenceValue(
                          LunioRepository.fuelGradePreferenceKey,
                          grade.code,
                        );
                    invalidateFuelPreferenceProviders(ref);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// 手填油价 sheet：只针对当前"省+油品"组合填一个价。
  Future<void> _editManualPrice(BuildContext context, WidgetRef ref) async {
    final province = ref.read(fuelProvinceProvider).value ?? '';
    final grade = ref.read(fuelGradeProvider).value;
    final current = ref.read(fuelManualPriceProvider).value;
    final controller = TextEditingController(
      text: current?.toStringAsFixed(2) ?? '',
    );
    await showLunioModalSheet<void>(
      context: context,
      builder: (sheetContext) {
        return PrototypeSheetFrame(
          title: '手填油价',
          subtitle: '$province · ${grade?.label ?? ''}，单位元/升。',
          bottomInset: MediaQuery.of(sheetContext).viewInsets.bottom,
          child: _ManualPriceForm(
            controller: controller,
            onSubmit: (price) async {
              await ref
                  .read(lunioRepositoryProvider)
                  .setFuelManualPrice(
                    province: province,
                    grade: grade!,
                    pricePerLiter: price,
                  );
              ref.invalidate(fuelManualPriceProvider);
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
              }
              if (context.mounted) {
                showStatusOverlay(
                  context,
                  price == null ? '已清除手填价' : '手填油价已保存',
                  StatusOverlayTone.success,
                );
              }
            },
          ),
        );
      },
    );
  }

  /// 清除手填：写 null 删该组合的键，回到数据源价格。
  Future<void> _clearManualPrice(BuildContext context) async {
    final ref = ProviderScope.containerOf(context, listen: false);
    final province = ref.read(fuelProvinceProvider).value;
    final grade = ref.read(fuelGradeProvider).value;
    if (province == null || grade == null) {
      return;
    }
    await ref
        .read(lunioRepositoryProvider)
        .setFuelManualPrice(province: province, grade: grade, pricePerLiter: null);
    ref.invalidate(fuelManualPriceProvider);
    if (context.mounted) {
      showStatusOverlay(context, '已清除手填价', StatusOverlayTone.success);
    }
  }

  /// 手动刷新：失败时 toast 提示（数据保留上次结果）。
  Future<void> _manualRefresh(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(fuelPriceControllerProvider.notifier).manualRefresh();
    if (context.mounted) {
      showStatusOverlay(
        context,
        ok ? '油价已刷新' : '油价刷新失败，展示上次数据',
        ok ? StatusOverlayTone.success : StatusOverlayTone.error,
      );
    }
  }
}

/// 副标题里可点的一段设置值（如"湖北"、"92#"）：文字 + 小下箭头提示可点。
class _SettingHotspot extends StatelessWidget {
  const _SettingHotspot({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 14, color: tokens.muted),
          ],
        ),
      ),
    );
  }
}

/// 选择列表（省份 sheet 用）：单列选项，选中项对勾标记。
/// 内容区限高滚动（与其他 sheet 高度统一），打开时定位到选中行。
/// 油品只有 4 项，不走这里（用 [_GradeChip] 一行胶囊，见 _pickGrade）。
class _SheetOptionList extends StatefulWidget {
  const _SheetOptionList({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final Future<void> Function(String label) onSelected;

  @override
  State<_SheetOptionList> createState() => _SheetOptionListState();
}

class _SheetOptionListState extends State<_SheetOptionList> {
  /// 单行固定高度（保证初始定位的滚动偏移量算得准）。
  static const double _rowExtent = 40;

  /// 内容区可见高度 ≈ 其他表单 sheet 的自然高度，视觉保持统一。
  static const double _viewportExtent = 320;

  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final maxOffset = (widget.labels.length * _rowExtent - _viewportExtent)
        .clamp(0.0, double.infinity);
    _controller = ScrollController(
      initialScrollOffset: (widget.selectedIndex * _rowExtent).clamp(
        0.0,
        maxOffset,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // maxHeight 兜底：选项多时限高滚动（与其他 sheet 高度统一）；
    // shrinkWrap 让选项少时按内容收缩（弹窗骨架的 Column 给的是无界
    // 高度，ListView 不收缩会布局失败，整个弹窗弹不出来）。
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _viewportExtent),
      child: ListView(
        controller: _controller,
        shrinkWrap: widget.labels.length <= 5,
        children: [
          for (final (index, label) in widget.labels.indexed)
            SizedBox(
              height: _rowExtent,
              child: _SheetOptionRow(
                label: label,
                selected: index == widget.selectedIndex,
                onTap: () async {
                  Navigator.of(context).pop();
                  await widget.onSelected(label);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 油品胶囊选项（油品 sheet 单行单选用，共 4 个）：
/// 选中主色、未选中中性色，高度/圆角/字号按 DESIGN.md 的 chip 规范。
class _GradeChip extends StatelessWidget {
  const _GradeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: selected ? tokens.primarySoft : tokens.surface2,
          foregroundColor: selected ? tokens.primary : tokens.ink,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
            side: BorderSide(color: selected ? tokens.primary : tokens.line),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// sheet 里的单行选项（省份/油品列表用，右侧对勾标记当前项）。
class _SheetOptionRow extends StatelessWidget {
  const _SheetOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? tokens.primary : tokens.ink,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 18, color: tokens.primary),
          ],
        ),
      ),
    );
  }
}

/// 手填油价表单（两位小数以内的每升价，0.01–99.99）。
class _ManualPriceForm extends StatefulWidget {
  const _ManualPriceForm({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final Future<void> Function(double? price) onSubmit;

  @override
  State<_ManualPriceForm> createState() => _ManualPriceFormState();
}

class _ManualPriceFormState extends State<_ManualPriceForm> {
  bool saving = false;
  String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          enabled: !saving,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}\.?\d{0,2}')),
          ],
          onSubmitted: (_) => saving ? null : _submit(),
          decoration: numberInputDecoration(suffixText: '元/升'),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 18),
        LunioFormActions(
          confirmLabel: '保存手填价',
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final text = widget.controller.text.trim();
    final price = double.tryParse(text);
    if (text.isEmpty) {
      // 清空输入框 = 清除手填价。
      setState(() {
        saving = true;
        errorText = null;
      });
      try {
        await widget.onSubmit(null);
      } catch (error) {
        if (mounted) {
          setState(() {
            saving = false;
            errorText = friendlyError(error);
          });
        }
      }
      return;
    }
    if (price == null || price <= 0 || price > 99.99) {
      setState(() => errorText = '请输入 0.01–99.99 之间的价格');
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(price);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = friendlyError(error);
      });
    }
  }
}

// ---------------- 加满预估卡（滚动定档的档位列表） ----------------

/// 档位行高（列表吸附与定高的基准，两处必须一致）。
const double _kTierRowExtent = 44;

/// 档位列表的整行吸附物理：惯性滚动结束时把第一行吸到整行边界。
/// 吸附放在弹道模拟里做，ScrollEnd 到达时偏移必然已对齐，可直接写库
/// （不能在 ScrollEnd 通知里再 animateTo——滚动活动收尾期间改活动
/// 会被滚动位置静默忽略）。
class _RowSnapScrollPhysics extends ScrollPhysics {
  const _RowSnapScrollPhysics({required this.rowExtent, super.parent});

  final double rowExtent;

  @override
  _RowSnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _RowSnapScrollPhysics(rowExtent: rowExtent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final maxIndex = (position.maxScrollExtent / rowExtent).floor();
    final targetIndex = (position.pixels / rowExtent)
        .round()
        .clamp(0, maxIndex);
    final target = targetIndex * rowExtent;
    if ((target - position.pixels).abs() <
        toleranceFor(position).distance * 2) {
      return null;
    }
    return ScrollSpringSimulation(spring, position.pixels, target, velocity);
  }
}

/// 档位列表卡：全量档位（100%→0%）滚动选择，第一行 = 剩余油量。
///
/// 交互规则（ADR 0002）：
///  - 窗口内可见 [_TierListCardState.visibleRows] 档，整表上下滚动
///    （第一行也跟着滚）；
///  - 滚动停稳自动吸附到整行，第一行所在的档位写库（fuel_predictions）；
///  - 右上角返回图标滚回默认 50%（停在 50% 时置灰）；
///  - 进入页面定位到已存档位在第一行；从没存过按 50% 定位、不写库。
class _TierListCard extends ConsumerStatefulWidget {
  const _TierListCard({
    required this.carId,
    required this.capacity,
    required this.savedPercent,
  });

  final int carId;

  /// 油箱容积（Car 上，v8 起按车存）；null 时无法算钱，显示引导。
  final double? capacity;

  /// 数据库里已存的档位（%）；null = 从没保存过（按 50% 定位）。
  final int? savedPercent;

  @override
  ConsumerState<_TierListCard> createState() => _TierListCardState();
}

class _TierListCardState extends ConsumerState<_TierListCard> {
  /// 每档一行的固定行高（滚动偏移量按它换算）。
  static const double _rowExtent = _kTierRowExtent;

  /// 窗口内可见档位数（产品确认：只显示 5 档）。
  static const int _visibleRows = 5;

  /// 默认档位 50% 在全量档位表里的下标。
  static final int _defaultIndex =
      (100 - 50) ~/ FuelRules.percentStep;

  late final ScrollController _controller;
  late int _firstIndex;
  late int _lastSavedPercent;

  /// 全量档位表（下标 0 = 100%，往后每档 -2%）。
  static final List<int> _tiers = FuelRules.allTierPercents;

  /// 已存档位 → 列表下标（奇数等非档位值就近取整，容错老数据）。
  static int _indexForPercent(int? percent) {
    final value = percent ?? 50;
    return ((100 - value) / FuelRules.percentStep)
        .round()
        .clamp(0, _tiers.length - 1);
  }

  @override
  void initState() {
    super.initState();
    _firstIndex = _indexForPercent(widget.savedPercent);
    _lastSavedPercent = _tiers[_firstIndex];
    _controller = ScrollController(
      initialScrollOffset: _firstIndex * _rowExtent,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 当前第一行对应的档位百分比。
  int get _currentPercent => _tiers[_firstIndex];

  @override
  Widget build(BuildContext context) {
    final price = ref.watch(_effectivePriceProvider);
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '加满预估',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Tooltip(
                message: '回到 50%',
                child: IconButton(
                  icon: const Icon(Icons.settings_backup_restore, size: 20),
                  onPressed: _currentPercent == 50
                      ? null
                      : _scrollBackToDefault,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (widget.capacity == null)
            const LunioInlineMessage(
              message: '先在"我的 → 车辆管理"里填写油箱容积，才能估算加满金额。',
            )
          else if (price == null)
            const LunioInlineMessage(
              message: '暂无油价数据，可刷新或手填油价后再来看预估。',
            )
          else
            _buildTierList(context, price),
        ],
      ),
    );
  }

  /// 滚动列表：定高窗口 + 每档定行高；滚动停稳吸附整行并落库。
  Widget _buildTierList(BuildContext context, double price) {
    final capacity = widget.capacity!;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: SizedBox(
        height: _visibleRows * _rowExtent,
        child: ListView.builder(
          controller: _controller,
          physics: const _RowSnapScrollPhysics(rowExtent: _kTierRowExtent),
          itemExtent: _rowExtent,
          // 底部留出"窗口高度 - 一行"的空白：否则滚到底时 0% 那档
          // 只能出现在窗口底部，永远到不了第一行。
          padding: EdgeInsets.only(bottom: (_visibleRows - 1) * _rowExtent),
          itemCount: _tiers.length,
          itemBuilder: (context, index) => _TierRow(
            percent: _tiers[index],
            liters: FuelRules.litersToFill(
              fuelPercent: _tiers[index],
              tankCapacityLiters: capacity,
            ),
            costCents: FuelRules.fullTankCostCents(
              fuelPercent: _tiers[index],
              tankCapacityLiters: capacity,
              pricePerLiter: price,
            ),
            isCurrent: index == _firstIndex,
          ),
        ),
      ),
    );
  }

  /// 滚动通知：跟随更新第一行下标（高亮 + 返回按钮状态）。
  /// 停稳（ScrollEnd）时吸附物理已把偏移对齐到整行边界，直接写库。
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final index = _indexFromOffset();
      if (index != _firstIndex) {
        setState(() => _firstIndex = index);
      }
      if (notification is ScrollEndNotification) {
        _persistBaselineIfChanged();
      }
    }
    return false;
  }

  /// 当前滚动偏移 → 第一行下标。
  int _indexFromOffset() {
    return (_controller.offset / _rowExtent).round().clamp(0, _tiers.length - 1);
  }

  /// 第一行档位变了就写库（滚动停稳后调用，偏移已被吸附物理对齐）。
  /// 写库失败回退记忆值，允许下次滚动重试。
  Future<void> _persistBaselineIfChanged() async {
    final percent = _currentPercent;
    if (percent == _lastSavedPercent) {
      return;
    }
    final previous = _lastSavedPercent;
    _lastSavedPercent = percent;
    try {
      await ref
          .read(lunioRepositoryProvider)
          .saveFuelPrediction(
            FuelPrediction(carId: widget.carId, fuelPercent: percent),
          );
      ref.invalidate(appliedCarFuelPredictionProvider);
    } catch (error) {
      _lastSavedPercent = previous;
      if (mounted) {
        showStatusOverlay(context, '油量保存失败，请重试', StatusOverlayTone.error);
      }
    }
  }

  /// 返回图标：滚回默认 50% 在第一行（停稳后由滚动通知写库）。
  void _scrollBackToDefault() {
    _controller.animateTo(
      _defaultIndex * _rowExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

/// 当前生效的每升价（手填优先，其次数据源价）；都没有为 null。
/// 档位金额随价联动，抽成 provider 让列表只在价格变化时重算。
final _effectivePriceProvider = Provider<double?>((ref) {
  final manualPrice = ref.watch(fuelManualPriceProvider).value;
  if (manualPrice != null) {
    return manualPrice;
  }
  final grade = ref.watch(fuelGradeProvider).value;
  final data = ref.watch(fuelPriceControllerProvider).value;
  if (grade == null) {
    return null;
  }
  return data?.priceFor(grade);
});

/// 单档金额行：档位% + 需要的油量 + 加满金额。第一行（基准档）高亮。
class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.percent,
    required this.liters,
    required this.costCents,
    required this.isCurrent,
  });

  final int percent;
  final double liters;
  final int costCents;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    // 行高由列表的 itemExtent 统一控制（44），这里只管横向布局。
    return Row(
      children: [
        Text(
          '$percent%',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isCurrent ? tokens.primary : tokens.ink,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '需 ${liters % 1 == 0 ? liters.toStringAsFixed(0) : liters.toStringAsFixed(1)} 升',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: tokens.muted,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '¥${(costCents / 100).toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isCurrent ? tokens.primary : tokens.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

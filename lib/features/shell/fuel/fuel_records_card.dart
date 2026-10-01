// 加油页第三张卡「加油记录」（ADR 0015，2026-09-22 重定义）：只填
// 日期/油品/单价/应付/实付五项的流水入口，容积（应付÷单价）由实体
// 预留落库、页面不展示。
//
// 页面结构（在 fuel_page 的油价卡与加满预估卡之后）：
//   - 头部「加油记录」+「记一笔」按钮（新增表单 sheet 入口）；
//   - 摘要行：累计加油金额（实付优先口径）+ 笔数；
//   - 记录行：日期 · 油品 + 实付（没填实付显示应付），下行单价 +
//     优惠小字；行点按进编辑；超过 5 条收进固定高度的卡内滚动窗口
//     （右侧滚动条、滑动时才显示拇指，2026-09-24 第五轮：删除
//     "展开全部/收起"按钮，免掉展开后要滚到底才能收起的来回横跳）；
//   - 空态：一行文案占位（不隐藏入口）。
//
// 数据流：watch appliedCarFuelRecordsProvider（按当前用车派生，写库后
// 由动作层整族失效自动刷新）。
//
// 表单（记一笔/编辑共用一个 sheet）：日期（上路日期起、**上限今天**，
// 不能未来）+ 油品（一行胶囊，默认 92#）+ 单价（与油价卡油品一致时
// 预填生效价，可改）+ 应付金额（必填）→ 箭头 → 实付金额（选填，点
// 箭头一键回填应付）。表单决策体（字段态、回填优先级、预填一次性
// 语义、快捷回填守卫、校验与提交载荷构造）在
// fuel_record_form_controller.dart 的 plain-Dart 控制器（单测镜像），
// 本文件只留渲染与事件转发。装载/守卫/pop/toast 时序归表单运行时
// showLunioFormSheet（ADR 0016）；保存/删除走动作层 saveFuelRecord /
// removeFuelRecord（ADR 0007）；删除只在编辑态出现，确认框在 sheet
// 入口函数弹。加油记录没有"同日查重"（同车同日多箱合法，ADR 0014）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/fuel_price.dart';
import '../../../domain/entities/fuel_record.dart';
import '../shared/shell_shared.dart';
import 'fuel_prices.dart';
import 'fuel_record_form_controller.dart';

/// 加油记录卡（加油页第三张卡）。
class FuelRecordsCard extends ConsumerStatefulWidget {
  const FuelRecordsCard({super.key});

  @override
  ConsumerState<FuelRecordsCard> createState() => _FuelRecordsCardState();
}

class _FuelRecordsCardState extends ConsumerState<FuelRecordsCard> {
  /// 卡内滚动窗口默认显示的最近条数（产品拍板：超过一屏太长）。
  static const int _visibleCount = 5;

  /// 单条记录行的固定槽高：行内上下 padding 16 + 正文两行实测 ~58
  /// （bodyMedium 14×1.55 + bodySmall 13×1.4 + 2 间距），取 60 留余量
  /// 防文字溢出。固定槽保证滚动窗口高度 = 恰好 [_visibleCount] 行。
  static const double _rowExtent = 60.0;

  /// 记录列表卡内滚动的控制器（超过 [_visibleCount] 条时挂右侧滚动条）。
  final ScrollController _listScroll = ScrollController();

  @override
  void dispose() {
    _listScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final recordsAsync = ref.watch(appliedCarFuelRecordsProvider);
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '加油记录',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SmallActionButton(
                label: '记一笔',
                primary: true,
                onPressed: () => showFuelRecordFormSheet(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 4),
          recordsAsync.when(
            skipLoadingOnReload: true,
            loading: () => Text(
              '读取中',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.muted,
              ),
            ),
            error: (error, stackTrace) => LunioInlineMessage(
              message: '加载失败：${friendlyError(error)}',
              tone: LunioStatusTone.danger,
            ),
            data: (records) => _buildBody(context, records),
          ),
        ],
      ),
    );
  }

  /// 卡主体：摘要行 + 记录行（倒序 = 最近优先）。超过 [_visibleCount]
  /// 条时收进固定高度的卡内滚动窗口（右侧滚动条，2026-09-26 起滑动时
  /// 才显示拇指；2026-09-24 第五轮拍板删除"展开全部/收起"按钮——展开
  /// 后要滚到底才能收起的来回横跳没了，滚轮直接看全部）；不超过则按
  /// 实际行数自然排布（无滚动条）。
  /// 记录为空时一行空态文案（不隐藏"记一笔"入口）。
  Widget _buildBody(BuildContext context, List<FuelRecord> records) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    if (records.isEmpty) {
      return Text(
        '还没有加油记录，点「记一笔」开始记录',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: tokens.muted,
        ),
      );
    }
    // 摘要行：累计加油金额（实付优先，没填取应付）+ 笔数。
    final totalCents = records.fold(
      0,
      (sum, record) => sum + record.effectiveCostCents,
    );
    final newestFirst = records.reversed.toList();
    Widget row(FuelRecord record) => _FuelRecordRow(
          record: record,
          onEdit: () => showFuelRecordFormSheet(context, ref, record: record),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          '累计加油 ${formatMoneyCents(totalCents)} · ${records.length} 笔',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: tokens.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        if (records.length > _visibleCount)
          // 超量：固定 [_visibleCount] 行高的卡内滚动窗口（2026-10-01 起
          // 三明治收编为共享组件 LunioSnapScrollWindow：右侧 3dp 细滚动
          // 条滑动时淡入停稳淡出、内容右缩进给拇指让位——右对齐金额不与
          // 拇指重叠、停稳吸附整行——只对齐不记录，无写库；每行走组件
          // itemExtent 定槽，窗口高度恒等于整数行）。
          LunioSnapScrollWindow(
            controller: _listScroll,
            rowExtent: _rowExtent,
            visibleRows: _visibleCount,
            itemCount: newestFirst.length,
            itemBuilder: (context, index) => row(newestFirst[index]),
          )
        else
          for (final record in newestFirst) row(record),
      ],
    );
  }
}

/// 一条加油记录行：上行"日期 · 油品 + 金额"，下行"单价 + 优惠小字"。
/// 金额口径 = 实付优先、没填取应付（与统计一致）。整行可点进编辑
/// （不加冗余编辑图标）。
class _FuelRecordRow extends StatelessWidget {
  const _FuelRecordRow({required this.record, required this.onEdit});

  final FuelRecord record;
  final VoidCallback onEdit;

  /// 优惠小字：实付填了且低于应付才显示"省 ¥x"（实付 ≥ 应付不算省，
  /// 属用户自己的账，不做红字提示）。
  String? get _savedText {
    final actual = record.actualCents;
    if (actual == null || actual >= record.payableCents) {
      return null;
    }
    return '省 ${formatMoneyCents(record.payableCents - actual)}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: tokens.muted,
    );
    final saved = _savedText;
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  // 日期格式沿用记录页行的 ISO 紧凑形态（yyyy-MM-dd）。
                  child: Text(
                    '${record.date} · ${record.grade.label}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatMoneyCents(record.effectiveCostCents),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatMoneyCents(record.unitPriceCents)}/升',
                    style: secondaryStyle,
                  ),
                ),
                if (saved != null) Text(saved, style: secondaryStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ★ 加油记录表单入口（记一笔按钮 / 记录行点按）：装载车辆与生效今天
/// → 弹表单 sheet。[record] 非 null 即编辑态（多一个删除入口）。
/// 新增时读生效价做单价预填（油价卡油品 = 默认 92# 才预填，见
/// [FuelRecordForm.prefillUnitPrice] 注释）；装载/守卫/pop/toast 时序归
/// showLunioFormSheet（ADR 0016），删除确认框留在入口（破坏性操作的
/// 文案属 UI 决策）、写库经动作层 removeFuelRecord（ADR 0007）。
Future<void> showFuelRecordFormSheet(
  BuildContext context,
  WidgetRef ref, {
  FuelRecord? record,
}) {
  // 装载结果写入闭包捕获变量，在 load/guard/builder 之间共享（ADR 0016）。
  Car? car;
  LocalDate today = LocalDate.fromDateTime(DateTime.now());
  double? prefillUnitPrice;
  return showLunioFormSheet<void>(
    context: context,
    title: record == null ? '记一笔加油' : '编辑加油记录',
    load: (handle) async {
      car = await ref.read(appliedCarProvider.future);
      today = await ref.read(effectiveTodayProvider.future);
      // 新增态的单价预填：油价卡当前油品恰是表单默认的 92# 时，把生效价
      // （手填价 > 数据源价）填进输入框；油品不一致不预填（价格张冠李戴
      // 比空着更糟）。编辑态用记录自己的单价，不读生效价。
      if (record == null) {
        final globalGrade = ref.read(fuelGradeProvider).value;
        if (globalGrade == FuelGrade.gasoline92) {
          prefillUnitPrice = ref.read(effectiveFuelPriceProvider);
        }
      }
      // 闭包捕获变量不做类型提升（装载数据跨闭包共享的标准写法），
      // 先落本地再判空。
      final loadedCar = car;
      if (loadedCar != null) {
        handle.setSubtitle('${loadedCar.brand} ${loadedCar.model}');
      }
    },
    guard: () => car?.id == null ? '请先新增车辆' : null,
    builder: (sheetContext, handle) {
      return FuelRecordForm(
        car: car!,
        today: today,
        record: record,
        prefillUnitPrice: prefillUnitPrice,
        handle: handle,
        // 写库+失效收进动作层（ADR 0007）；关 sheet 与成功 toast 归表单
        // 运行时（ADR 0016）。
        onSubmit: (value) => saveFuelRecord(ref, value),
        onDelete: record == null
            ? null
            : () async {
                // 删除确认框在入口弹（破坏性操作，文案属 UI 决策），
                // 写库经动作层 removeFuelRecord（ADR 0007）：失败行走
                // handle.run 的行内错误位，成功 pop + toast 归运行时。
                final confirmed = await showConfirmDialog(
                  context: context,
                  title: '删除加油记录',
                  message: '确定删除 ${record.date} 的加油记录？',
                  confirmLabel: '删除',
                );
                if (confirmed != true || !context.mounted) {
                  return;
                }
                await handle.run(() => removeFuelRecord(ref, record.id!));
                // run 失败时错误已写行内错误位（sheet 留场）；只有删除
                // 成功（errorText 仍为空）才关场 + 成功 toast。
                if (context.mounted && handle.errorText == null) {
                  handle.close(toast: '加油记录已删除');
                }
              },
      );
    },
    successMessage: '加油记录已保存',
  );
}

/// 加油记录表单（新增/编辑共用）：日期（上路日期起、上限今天）+ 油品
/// 一行胶囊（默认 92#）+ 单价（预填生效价，可改）+ 应付金额（必填）
/// → 箭头 → 实付金额（选填，点箭头一键回填应付）。编辑态底部多一个
/// 删除按钮（确认框在 sheet 入口函数里弹）。表单决策体（字段态、回填
/// 优先级、预填一次性语义、快捷回填守卫、校验与提交载荷构造）收在
/// FuelRecordFormController（fuel_record_form_controller.dart，同
/// RecordFormController 先例），本 widget 只渲染字段、注入日期选择器
/// 实现并转发事件。
class FuelRecordForm extends StatefulWidget implements FormSheetHandleWidget {
  const FuelRecordForm({
    required this.car,
    required this.today,
    required this.handle,
    required this.onSubmit,
    this.record,
    this.prefillUnitPrice,
    this.onDelete,
  });

  final Car car;
  final LocalDate today;

  /// 编辑态的既有记录（null = 新增）。
  final FuelRecord? record;

  /// 新增态的单价预填值（元/升，来自生效价；null = 不预填）。编辑态
  /// 忽略此值（回填记录自己的单价）。只在开表单时生效一次——之后切换
  /// 油品胶囊不重算预填，避免覆盖用户已输入的价格。
  final double? prefillUnitPrice;

  /// 表单运行时把手（ADR 0016）：saving/行内错误/提交/关闭都经它。
  @override
  final FormSheetHandle<void> handle;

  /// 保存回调（构造实体后调用，实现在入口函数里接动作层）。
  final Future<void> Function(FuelRecord record) onSubmit;

  /// 删除回调（仅编辑态非 null；确认框在回调里）。
  final Future<void> Function()? onDelete;

  @override
  State<FuelRecordForm> createState() => _FuelRecordFormState();
}

class _FuelRecordFormState extends State<FuelRecordForm>
    with FormSheetHandleHost<FuelRecordForm> {
  // ---- 提交运行时（ADR 0016）：本 State 只做渲染与事件转发，错误文案
  // 经把手显示（宿主监听重建），控制器的报错经注入闭包落到把手。

  /// 表单决策体（fuel_record_form_controller.dart）：字段态、回填优先级、
  /// 快捷回填守卫、校验与提交载荷构造都在里面，本 State 持有生命周期
  /// 并转发事件（同 MaintenanceRecordFormState 接法）。
  late final FuelRecordFormController form;

  bool get isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    form = FuelRecordFormController(
      car: widget.car,
      today: widget.today,
      record: widget.record,
      prefillUnitPrice: widget.prefillUnitPrice,
      ui: FuelRecordFormUi(
        // 生命周期守卫在注入闭包里（widget 的 mounted 是唯一可信的
        // 生命周期真值）：选择器 await 期间表单可能已被卸载，未挂载按
        // 取消（null）返回，不再碰 context。
        pickDate: (initial, first, last) async {
          if (!mounted) {
            return null;
          }
          return showSimpleDatePicker(
            context,
            initialDate: initial,
            firstDate: first,
            lastDate: last,
            today: widget.today,
          );
        },
      ),
      reportError: (text) {
        if (mounted) {
          setFormError(text);
        }
      },
    );
  }

  @override
  void dispose() {
    form.dispose();
    super.dispose();
  }

  /// 点中间箭头：控制器守卫 + 回填，这里只负责重建。
  void _copyPayableToActual() {
    form.copyPayableToActual();
    setState(() {});
  }

  /// 选加油日期：控制器弹注入的选择器并落新日期（边界判定在控制器），
  /// 这里只负责重建日期行。
  Future<void> _pickDate() async {
    await form.pickRecordDate();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LunioPickerTile(
          label: '加油日期',
          value: formatDateForUser(form.recordDate),
          enabled: !saving,
          onTap: _pickDate,
        ),
        const SizedBox(height: 10),
        // 油品一行胶囊：固定 4 项（与油价卡油品 sheet 同一份枚举），
        // 点选即换，默认 92#。
        Row(
          children: [
            Text('油品', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  for (final option in FuelGrade.values) ...[
                    _GradeChip(
                      grade: option,
                      selected: option == form.grade,
                      enabled: !saving,
                      onTap: () => setState(() => form.setGrade(option)),
                    ),
                    if (option != FuelGrade.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LunioNumberField(
          controller: form.unitPriceController,
          enabled: !saving,
          labelText: '单价',
          suffixText: '元/升',
          decimals: 2,
        ),
        const SizedBox(height: 10),
        // 应付 → 箭头 → 实付：箭头既是流向示意也是快捷按钮（点它把
        // 应付回填进实付），实付留空 = 无优惠。
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LunioNumberField(
                controller: form.payableController,
                enabled: !saving,
                labelText: '应付金额',
                suffixText: '元',
                decimals: 2,
              ),
            ),
            IconButton(
              onPressed: saving ? null : _copyPayableToActual,
              icon: const Icon(Icons.east),
              tooltip: '同应付',
            ),
            Expanded(
              child: LunioNumberField(
                controller: form.actualController,
                enabled: !saving,
                labelText: '实付（选填）',
                suffixText: '元',
                decimals: 2,
              ),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        LunioFormActions(
          confirmLabel: isEditing ? '保存修改' : '保存',
          onCancel: () => widget.handle.close(),
          onConfirm: _submit,
          saving: saving,
        ),
        if (isEditing) ...[
          const SizedBox(height: 8),
          Center(
            child: SmallActionButton(
              label: '删除',
              danger: true,
              onPressed: saving ? null : widget.onDelete,
            ),
          ),
        ],
      ],
    );
  }

  /// 提交：控制器校验并构造载荷（失败已报行内错误、留场），非 null 交给
  /// 表单运行时的提交生命周期（ADR 0016）→ 动作层写库（ADR 0007）。
  Future<void> _submit() async {
    final record = form.submitPayload();
    if (record == null) {
      return;
    }
    await widget.handle.submit(() => widget.onSubmit(record));
  }
}

/// 油品胶囊（表单内一行单选，共 4 个）：选中用主色底、未选中描边。
/// 纯视觉小件，与油价卡油品 sheet 的胶囊同语言（那里是 sheet 版）。
class _GradeChip extends StatelessWidget {
  const _GradeChip({
    required this.grade,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final FuelGrade grade;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? tokens.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            border: Border.all(
              color: selected ? tokens.primary : tokens.line,
            ),
          ),
          child: Text(
            grade.label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : tokens.ink,
            ),
          ),
        ),
      ),
    );
  }
}

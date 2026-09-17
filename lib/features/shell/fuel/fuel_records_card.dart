// 加油页第三张卡「加油记录」（ADR 0014）：30 秒记一笔的流水入口。
//
// 页面结构（在 fuel_page 的油价卡与加满预估卡之后）：
//   - 头部「加油记录」+「记一笔」按钮（新增表单 sheet 入口）；
//   - 摘要行：平均油耗 + 每公里油费（满箱段口径，无有效段不显示）；
//   - 记录行：日期 · 里程 / 金额 + 升数 / 本段油耗，行点按进编辑；
//     默认只显示最近 5 条，超出折叠，可「展开全部」/「收起」；
//   - 空态：一行文案占位（不隐藏入口，用户故事 35）。
//
// 数据流：watch appliedCarFuelRecordsProvider（按当前用车派生，写库后
// 由动作层整族失效自动刷新）；满箱段划分与均值全部调 FuelRules 纯函数，
// 本文件不做口径计算（≈ Java 里 Service 只编排，算法在 Domain 层）。
//
// 表单（记一笔/编辑共用一个 sheet）：五项字段 + 单价只读展示，保存走
// 表单提交运行器 mixin + 动作层 saveFuelRecord；删除只在编辑态出现，
// 确认框在调用方（本文件的 sheet 入口函数）弹、动作经动作层
// removeFuelRecord（ADR 0007）。加油记录没有"同日查重"（同车同日多箱
// 合法，ADR 0014），也没有里程软提示（不联动车辆里程），表单比保养
// 记录的简单一个量级。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/fuel_record.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/rules/fuel_rules.dart';
import '../shared/shell_shared.dart';

/// 加油记录卡（加油页第三张卡）。
class FuelRecordsCard extends ConsumerStatefulWidget {
  const FuelRecordsCard({super.key});

  @override
  ConsumerState<FuelRecordsCard> createState() => _FuelRecordsCardState();
}

class _FuelRecordsCardState extends ConsumerState<FuelRecordsCard> {
  /// 折叠态默认显示的最近条数（产品拍板：超过一屏太长，默认收 5 条）。
  static const int _collapsedCount = 5;

  /// 是否展开全部（只影响显示条数，不影响口径计算——摘要与每行本段
  /// 油耗始终按全量记录算）。
  bool _expanded = false;

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
                  style: Theme.of(context).textTheme.titleMedium,
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

  /// 卡主体：摘要行 + 记录行（倒序 = 最近优先，折叠截断）+ 展开开关。
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
    // 满箱段一次算全量：摘要行与行内"本段油耗"共用同一份段划分。
    final segments = FuelRules.fuelTankSegments(records);
    final segmentByRecordId = <int, FuelTankSegment>{
      for (final segment in segments) segment.closingRecordId: segment,
    };
    final average = FuelRules.averageFuelConsumptionPer100Km(segments);
    final costPerKm = FuelRules.averageCostPerKm(segments);
    final newestFirst = records.reversed.toList();
    final visibleRows = _expanded
        ? newestFirst
        : newestFirst.take(_collapsedCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (average != null && costPerKm != null) ...[
          const SizedBox(height: 4),
          Text(
            '平均油耗 ${average.toStringAsFixed(1)} L/100km · '
            '每公里 ¥${costPerKm.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
        ],
        for (final record in visibleRows) ...[
          _FuelRecordRow(
            record: record,
            segment: segmentByRecordId[record.id],
            onEdit: () => showFuelRecordFormSheet(context, ref, record: record),
          ),
        ],
        if (records.length > _collapsedCount)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起' : '展开全部'),
            ),
          ),
      ],
    );
  }
}

/// 一条加油记录行：两行布局——上行"日期 · 里程 + 金额"，下行
/// "升数 + 本段油耗"。整行可点进编辑（不加冗余编辑图标）。
/// [segment] 为 null 显示占位"—"：没有闭合段（首条满箱、部分加油、
/// 段里程非增折叠）都不显示油耗，与摘要行"无有效段不显示"同口径。
class _FuelRecordRow extends StatelessWidget {
  const _FuelRecordRow({
    required this.record,
    required this.segment,
    required this.onEdit,
  });

  final FuelRecord record;
  final FuelTankSegment? segment;
  final VoidCallback onEdit;

  /// 本段油耗：该行闭合的满箱段自身油耗，公式收在
  /// [FuelTankSegment.consumptionPer100Km]（段恒有效，直接取）。
  String? get _segmentConsumptionText {
    final segment = this.segment;
    if (segment == null) {
      return null;
    }
    return '${segment.consumptionPer100Km.toStringAsFixed(1)} L/100km';
  }

  /// 升数固定两位小数（与金额对齐，油机跳枪数就是两位）。
  String get _volumeText => '${record.volumeLiters.toStringAsFixed(2)} 升';

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: tokens.muted,
    );
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
                    '${record.date} · ${formatNumber(record.mileageKm)} km',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatMoneyCents(record.totalCostCents),
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
                Expanded(child: Text(_volumeText, style: secondaryStyle)),
                Text(
                  _segmentConsumptionText ?? '—',
                  style: secondaryStyle,
                ),
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
/// onSubmit/onDelete 已在闭包里接动作层；确认框/toast/pop 留调用方
/// （ADR 0007 的"调用方"指动作层的调用方，即本函数）。
Future<void> showFuelRecordFormSheet(
  BuildContext context,
  WidgetRef ref, {
  FuelRecord? record,
}) async {
  final car = await ref.read(appliedCarProvider.future);
  final today = await ref.read(effectiveTodayProvider.future);
  if (!context.mounted) {
    return;
  }
  if (car?.id == null) {
    showStatusOverlay(context, '请先新增车辆', StatusOverlayTone.info);
    return;
  }
  await showLunioModalSheet<void>(
    context: context,
    // 表单有未保存输入：点遮罩/下滑不关（与其他编辑表单同一口径）。
    barrierDismissible: false,
    builder: (sheetContext) {
      return PrototypeSheetFrame(
        title: record == null ? '记一笔加油' : '编辑加油记录',
        subtitle: '${car!.brand} ${car.model}',
        // 必须用 sheet 自己的 context 取键盘高度（外层 context 在 sheet
        // 构建时定格为 0，见 records_page 同款注释）。
        bottomInset: MediaQuery.of(sheetContext).viewInsets.bottom,
        child: FuelRecordForm(
          car: car,
          today: today,
          record: record,
          onSubmit: (value) async {
            // 写库+失效收进动作层（ADR 0007），这里只留反馈薄壳。
            await saveFuelRecord(ref, value);
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
            if (context.mounted) {
              showStatusOverlay(
                context,
                '加油记录已保存',
                StatusOverlayTone.success,
              );
            }
          },
          onDelete: record == null
              ? null
              : () async {
                  // 删除确认框在调用方弹（破坏性操作，文案属 UI 决策），
                  // 写库经动作层 removeFuelRecord。
                  final confirmed = await showConfirmDialog(
                    context: context,
                    title: '删除加油记录',
                    message: '确定删除 ${record.date} 的加油记录？',
                    confirmLabel: '删除',
                  );
                  if (confirmed != true) {
                    return;
                  }
                  await removeFuelRecord(ref, record.id!);
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                  if (context.mounted) {
                    showStatusOverlay(
                      context,
                      '加油记录已删除',
                      StatusOverlayTone.success,
                    );
                  }
                },
        ),
      );
    },
  );
}

/// 加油记录表单（新增/编辑共用）：日期（范围同保养记录：上路日期起、
/// 允许未来）+ 里程/金额/升数（统一数字输入组件）+ 加满开关（默认开）
/// + 单价只读行（金额 ÷ 升数，两个输入齐了才显示数值）。编辑态底部
/// 多一个删除按钮（确认框在 sheet 入口函数里弹）。
class FuelRecordForm extends StatefulWidget {
  const FuelRecordForm({
    required this.car,
    required this.today,
    required this.onSubmit,
    this.record,
    this.onDelete,
  });

  final Car car;
  final LocalDate today;

  /// 编辑态的既有记录（null = 新增）。
  final FuelRecord? record;

  /// 保存回调（构造实体后调用，实现在入口函数里接动作层）。
  final Future<void> Function(FuelRecord record) onSubmit;

  /// 删除回调（仅编辑态非 null；确认框在回调里）。
  final Future<void> Function()? onDelete;

  @override
  State<FuelRecordForm> createState() => _FuelRecordFormState();
}

class _FuelRecordFormState extends State<FuelRecordForm> with LunioFormSubmit {
  late LocalDate recordDate;
  late final TextEditingController mileageController;
  late final TextEditingController costController;
  late final TextEditingController volumeController;

  /// 是否加满（新增默认开：大多数加油都加满，少点一次开关）。
  late bool fullTank;

  bool get isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    recordDate = record?.date ?? widget.today;
    mileageController = TextEditingController(
      text: record?.mileageKm.toString() ?? '',
    );
    costController = TextEditingController(
      text: record == null ? '' : formatMoneyText(record.totalCostCents),
    );
    // 升数直接回填原值（toString 去掉多余的 0，如 40.0 → "40.0"）。
    volumeController = TextEditingController(
      text: record?.volumeLiters.toString() ?? '',
    );
    fullTank = record?.fullTank ?? true;
  }

  @override
  void dispose() {
    mileageController.dispose();
    costController.dispose();
    volumeController.dispose();
    super.dispose();
  }

  /// 单价 = 金额 ÷ 升数（元/升）。金额或升数没填/升数非正时不显示，
  /// 只给占位（不可手填——拍板：单价自动算，杜绝与金额/升数矛盾）。
  double? get _unitPrice {
    final cost = double.tryParse(costController.text);
    final volume = double.tryParse(volumeController.text);
    if (cost == null || volume == null || volume <= 0) {
      return null;
    }
    return cost / volume;
  }

  /// 选加油日期：范围同保养记录（上路日期起、允许未来）。没有同日
  /// 查重——同车同日多箱合法（ADR 0014）。
  Future<void> _pickDate() async {
    final picked = await showSimpleDatePicker(
      context,
      initialDate: recordDate,
      firstDate: widget.car.roadDate,
      lastDate: LocalDate.fromDateTime(
        widget.today.toDateTime().add(const Duration(days: 365)),
      ),
      today: widget.today,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => recordDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final unitPrice = _unitPrice;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LunioPickerTile(
          label: '加油日期',
          value: formatDateForUser(recordDate),
          enabled: !saving,
          onTap: _pickDate,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: LunioNumberField(
                controller: mileageController,
                enabled: !saving,
                labelText: '里程',
                suffixText: 'km',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioNumberField(
                controller: costController,
                enabled: !saving,
                labelText: '金额',
                suffixText: '元',
                decimals: 2,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LunioNumberField(
          controller: volumeController,
          enabled: !saving,
          labelText: '升数',
          suffixText: '升',
          decimals: 2,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '加满',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Switch(
              value: fullTank,
              onChanged: saving
                  ? null
                  : (value) => setState(() => fullTank = value),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('单价', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            Text(
              unitPrice == null ? '—' : '${unitPrice.toStringAsFixed(2)} 元/升',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
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
          onCancel: () => Navigator.of(context).pop(),
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

  /// 校验 + 构造实体 + 提交：里程非负整数、金额非负数字、升数 > 0
  /// （与实体 validate 同口径，提前给中文行内错误）。金额元→分四舍五入。
  Future<void> _submit() async {
    final mileage = int.tryParse(mileageController.text);
    final cost = double.tryParse(costController.text);
    final volume = double.tryParse(volumeController.text);
    if (mileage == null || mileage < 0) {
      setFormError('里程必须是非负整数');
      return;
    }
    if (cost == null || cost < 0) {
      setFormError('金额必须是非负数字');
      return;
    }
    if (volume == null || volume <= 0) {
      setFormError('升数必须大于 0');
      return;
    }
    final record = FuelRecord(
      id: widget.record?.id,
      carId: widget.car.id!,
      date: recordDate,
      mileageKm: mileage,
      volumeLiters: volume,
      totalCostCents: (cost * 100).round(),
      fullTank: fullTank,
      sync: SyncMetadata(
        status: isEditing ? SyncStatus.pendingUpdate : SyncStatus.pendingCreate,
        updatedAt: DateTime.now(),
      ),
    );
    await runSubmit(() => widget.onSubmit(record));
  }
}

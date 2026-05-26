import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/date/local_date.dart';
import '../../core/platform/native_files.dart';
import '../../core/theme/lunio_tokens.dart';
import '../../core/widgets/lunio_components.dart';
import '../../data/backup/backup_codec.dart';
import '../../domain/entities/car.dart';
import '../../domain/entities/maintenance_item.dart';
import '../../domain/entities/maintenance_record.dart';
import '../../domain/entities/reminder.dart';
import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_model.dart';
import '../../domain/rules/maintenance_rules.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final pages = [
      const _ReminderPreviewPage(),
      const _RecordsPreviewPage(),
      const _ProfilePreviewPage(),
    ];

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(child: pages[selectedIndex]),
      floatingActionButton: selectedIndex == 2
          ? null
          : FloatingActionButton(
              onPressed: () {
                _dismissTransientUi(context);
                _showMaintenanceRecordFormSheet(context, ref);
              },
              tooltip: '新增保养记录',
              backgroundColor: tokens.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusLarge),
              ),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(tokens.radiusXl),
            border: Border.all(color: tokens.line.withValues(alpha: 0.9)),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.16),
                blurRadius: 46,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _BottomNavItem(
                  icon: Icons.home_repair_service_outlined,
                  selectedIcon: Icons.home_repair_service,
                  label: '提醒',
                  selected: selectedIndex == 0,
                  onTap: () {
                    _dismissTransientUi(context);
                    context.go('/reminders');
                  },
                ),
                const SizedBox(width: 6),
                _BottomNavItem(
                  icon: Icons.format_list_bulleted_outlined,
                  selectedIcon: Icons.format_list_bulleted,
                  label: '记录',
                  selected: selectedIndex == 1,
                  onTap: () {
                    _dismissTransientUi(context);
                    context.go('/records');
                  },
                ),
                const SizedBox(width: 6),
                _BottomNavItem(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: '我的',
                  selected: selectedIndex == 2,
                  onTap: () {
                    _dismissTransientUi(context);
                    context.go('/me');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final foreground = selected ? Colors.white : tokens.muted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: selected ? tokens.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  color: foreground,
                  size: 21,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderPreviewPage extends ConsumerWidget {
  const _ReminderPreviewPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appliedCar = ref.watch(appliedCarProvider);
    final cars = ref.watch(carsProvider);
    final items = ref.watch(appliedCarMaintenanceItemsProvider);
    final records = ref.watch(appliedCarRecordsProvider);
    final today = ref.watch(effectiveTodayProvider);
    final canSwitchCar = cars.maybeWhen(
      data: (value) => value.length > 1,
      orElse: () => false,
    );
    return appliedCar.when(
      loading: () => const _LoadingPage(title: '保养提醒'),
      error: (error, stackTrace) => _ErrorPage(title: '保养提醒', error: error),
      data: (car) => LunioPage(
        title: '保养提醒',
        subtitle: '按当前应用车辆计算里程与时间进度',
        trailing: canSwitchCar
            ? LunioIconButton(
                icon: Icons.directions_car_outlined,
                tooltip: '切换车辆',
                onPressed: () => _showVehicleSwitcher(context, ref),
              )
            : null,
        children: [
          if (car == null)
            _EmptyVehicleCard(onAdd: () => _showAddCarSheet(context, ref))
          else
            LunioHeroCard(
              title: '${car.brand} ${car.model}',
              subtitle: '上路 ${car.roadDate} · 当前应用车辆',
              actionLabel: canSwitchCar ? '切换' : null,
              onAction: canSwitchCar
                  ? () => _showVehicleSwitcher(context, ref)
                  : null,
              metrics: [
                LunioMetric(
                  label: '当前里程',
                  value: _formatNumber(car.currentMileageKm),
                ),
                LunioMetric(
                  label: '最急项目',
                  value: today.when(
                    loading: () => '计算中',
                    error: (error, stackTrace) => '日期失败',
                    data: (value) =>
                        _mostUrgentText(items, records, car, value),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.add,
                  title: '新增保养记录',
                  subtitle: '保存后同步更新车辆里程',
                  onTap: () => _showMaintenanceRecordFormSheet(context, ref),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.format_list_bulleted,
                  title: '查看历史',
                  subtitle: '按周期或按项目管理记录',
                  onTap: () => context.go('/records'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (car != null)
            LunioSection(
              title: '待关注项目',
              trailing: TextButton(
                onPressed: () => _showMaintenanceItemsSheet(context, ref),
                child: const Text('管理项目'),
              ),
              children: [
                today.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) =>
                      LunioCard(child: Text('日期加载失败：${_friendlyError(error)}')),
                  data: (value) => _ReminderList(
                    car: car,
                    items: items,
                    records: records,
                    today: value,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(tokens.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: tokens.line),
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.08),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tokens.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: tokens.primary, size: 18),
              ),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: index == 0 ? tokens.primarySoft : tokens.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: index == 0
                      ? tokens.primary.withValues(alpha: 0.34)
                      : tokens.line,
                ),
              ),
              child: Text(
                labels[index],
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: index == 0 ? tokens.primary : tokens.ink,
                ),
              ),
            ),
            if (index != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ItemPills extends StatelessWidget {
  const _ItemPills({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final label in labels)
          Container(
            constraints: const BoxConstraints(minHeight: 28),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: tokens.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xff354035),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: danger ? tokens.dangerSoft : tokens.surface2,
          foregroundColor: danger ? tokens.danger : tokens.ink,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _PrototypeSheetFrame extends StatelessWidget {
  const _PrototypeSheetFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.heightFactor,
    this.bottomInset = 0,
    this.trailing,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final double? heightFactor;
  final double bottomInset;
  final Widget? trailing;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottomInset),
      child: Column(
        mainAxisSize: heightFactor == null
            ? MainAxisSize.min
            : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xffd4ddd4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          const SizedBox(height: 14),
          if (heightFactor == null) child else Expanded(child: child),
        ],
      ),
    );
    final sheet = Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.18),
            blurRadius: 54,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: scrollable && heightFactor == null
          ? SingleChildScrollView(child: content)
          : content,
    );
    if (heightFactor == null) {
      return sheet;
    }
    return FractionallySizedBox(heightFactor: heightFactor, child: sheet);
  }
}

class _ChoiceChipButton extends StatelessWidget {
  const _ChoiceChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.primarySoft : tokens.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? tokens.primary.withValues(alpha: 0.3)
                : tokens.line,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? tokens.primary : tokens.ink,
          ),
        ),
      ),
    );
  }
}

class _ReminderList extends StatelessWidget {
  const _ReminderList({
    required this.car,
    required this.items,
    required this.records,
    required this.today,
  });

  final Car car;
  final AsyncValue<List<MaintenanceItem>> items;
  final AsyncValue<List<MaintenanceRecord>> records;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    if (items.isLoading || records.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.hasError) {
      return LunioCard(child: Text('保养项目加载失败：${_friendlyError(items.error!)}'));
    }
    if (records.hasError) {
      return LunioCard(
        child: Text('保养记录加载失败：${_friendlyError(records.error!)}'),
      );
    }
    final rows = _buildReminderRows(
      car: car,
      items: items.value ?? const [],
      records: records.value ?? const [],
      today: today,
    );
    if (rows.isEmpty) {
      return LunioCard(
        child: Text(
          '暂无启用的保养项目，请先在“我的”里配置保养项目。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      children: [
        for (final row in rows) ...[
          _ReminderRow(row: row),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.row});

  final _ReminderViewData row;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final color = switch (row.tone) {
      LunioStatusTone.normal => tokens.success,
      LunioStatusTone.warning => tokens.warning,
      LunioStatusTone.danger => tokens.danger,
    };
    return LunioCard(
      child: Row(
        children: [
          SizedBox.square(
            dimension: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(58),
                  painter: _ReminderProgressRingPainter(
                    progress: row.progressValue,
                    color: color,
                    backgroundColor: tokens.surface3,
                  ),
                ),
                SizedBox(
                  width: 38,
                  height: 16,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      row.percentText,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    LunioStatusBadge(label: row.badge, tone: row.tone),
                  ],
                ),
                const SizedBox(height: 6),
                Text(row.detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderProgressRingPainter extends CustomPainter {
  const _ReminderProgressRingPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  final double progress;
  final Color color;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 6) / 2;
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    final foregroundPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius, backgroundPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      6.2832 * progress.clamp(0, 1),
      false,
      foregroundPaint,
    );
  }

  @override
  bool shouldRepaint(_ReminderProgressRingPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        color != oldDelegate.color ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}

class _RecordsPreviewPage extends ConsumerStatefulWidget {
  const _RecordsPreviewPage();

  @override
  ConsumerState<_RecordsPreviewPage> createState() =>
      _RecordsPreviewPageState();
}

class _RecordsPreviewPageState extends ConsumerState<_RecordsPreviewPage> {
  int selectedMode = 0;

  @override
  Widget build(BuildContext context) {
    final car = ref
        .watch(appliedCarProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final records = ref.watch(appliedCarRecordsProvider);
    final items = ref
        .watch(appliedCarMaintenanceItemsProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => const <MaintenanceItem>[],
        );
    return LunioPage(
      title: '保养记录',
      subtitle: '同车同日仅保留一条记录',
      trailing: LunioIconButton(
        icon: Icons.tune,
        tooltip: '筛选记录',
        onPressed: () => _showToast(context, '筛选入口已预留'),
      ),
      children: [
        LunioSegmentedControl(
          values: const ['按周期', '按项目'],
          selectedIndex: selectedMode,
          onSelected: (index) => setState(() => selectedMode = index),
        ),
        const SizedBox(height: 14),
        _FilterBar(
          labels: [
            '全部年份',
            '2026年',
            if (items.isNotEmpty) items.first.name,
            if (items.length > 1) items[1].name,
          ],
        ),
        const SizedBox(height: 14),
        records.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              LunioCard(child: Text('记录加载失败：${_friendlyError(error)}')),
          data: (value) {
            if (car == null) {
              return const LunioCard(child: Text('请先新增车辆'));
            }
            if (value.isEmpty) {
              return LunioCard(
                child: Text(
                  '暂无保养记录，点击右下角 + 新增。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            if (selectedMode == 0) {
              return _RecordCycleList(
                records: value,
                items: items,
                onEdit: (record) => _showMaintenanceRecordFormSheet(
                  context,
                  ref,
                  record: record,
                ),
                onDelete: (record) =>
                    _deleteMaintenanceRecord(context, ref, record),
              );
            }
            return _RecordItemList(records: value, items: items);
          },
        ),
      ],
    );
  }
}

class _RecordCycleList extends StatelessWidget {
  const _RecordCycleList({
    required this.records,
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MaintenanceRecord> records;
  final List<MaintenanceItem> items;
  final ValueChanged<MaintenanceRecord> onEdit;
  final ValueChanged<MaintenanceRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Column(
      children: [
        for (final record in records) ...[
          LunioCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.date.toString(),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      _formatMoney(record.costCents),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_formatNumber(record.mileageKm)} km · ${record.note ?? '未填写备注'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _ItemPills(labels: _recordItemNameList(record, items)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SmallActionButton(
                      label: '编辑',
                      onPressed: () => onEdit(record),
                    ),
                    const SizedBox(width: 8),
                    _SmallActionButton(
                      label: '删除',
                      danger: true,
                      onPressed: () => onDelete(record),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _RecordItemList extends StatelessWidget {
  const _RecordItemList({required this.records, required this.items});

  final List<MaintenanceRecord> records;
  final List<MaintenanceItem> items;

  @override
  Widget build(BuildContext context) {
    final rows = <({MaintenanceRecord record, MaintenanceItem? item})>[];
    for (final record in records) {
      for (final itemId in record.itemIds) {
        rows.add((record: record, item: _itemById(items, itemId)));
      }
    }
    return Column(
      children: [
        for (final row in rows) ...[
          LunioCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.item?.name ?? '未知项目',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${row.record.date} · ${_formatNumber(row.record.mileageKm)} km · ${_formatMoney(row.record.costCents)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SmallActionButton(label: '编辑项目记录', onPressed: () {}),
                    const SizedBox(width: 8),
                    _SmallActionButton(
                      label: '移除项目',
                      danger: true,
                      onPressed: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProfilePreviewPage extends ConsumerWidget {
  const _ProfilePreviewPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cars = ref.watch(carsProvider);
    final manualDate = ref.watch(manualDatePreferenceProvider);
    final themeMode = ref.watch(themeModePreferenceProvider);
    final appliedCar = ref
        .watch(appliedCarProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final hasCars = cars.maybeWhen(
      data: (value) => value.isNotEmpty,
      orElse: () => false,
    );
    return LunioPage(
      title: '个人中心',
      children: [
        LunioSection(
          title: '我的车辆',
          trailing: hasCars
              ? TextButton(
                  onPressed: () => _showAddCarSheet(context, ref),
                  child: const Text('添加'),
                )
              : null,
          children: [
            cars.when(
              loading: () => const LunioCard(child: Text('车辆加载中...')),
              error: (error, stackTrace) =>
                  LunioCard(child: Text('车辆加载失败：${_friendlyError(error)}')),
              data: (items) => _VehicleList(
                cars: items,
                appliedCarId: appliedCar?.id,
                onAdd: () => _showAddCarSheet(context, ref),
                onEdit: (car) => _showEditCarSheet(context, ref, car),
                onApply: (carId) => _applyCar(context, ref, carId),
                onDelete: (car) => _deleteCar(context, ref, car),
              ),
            ),
            const SizedBox(height: 10),
            _ProfileSettingRow(
              title: '保养项目',
              subtitle: appliedCar == null ? '先新增车辆' : '默认项目和自定义项目',
              trailingLabel: '管理',
              onTap: appliedCar == null
                  ? () => _showToast(context, '请先新增车辆')
                  : () => _showMaintenanceItemsSheet(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LunioSection(
          title: '数据与工具',
          children: [
            _ProfileSettingRow(
              title: 'JSON 备份',
              subtitle: '导出全部车辆、项目配置和保养记录',
              trailingLabel: '导出',
              onTap: () => _exportBackup(context, ref),
            ),
            _ProfileSettingRow(
              title: '恢复',
              subtitle: '先清空当前数据，再导入备份文件',
              trailingLabel: '恢复',
              onTap: () => _showRestoreBackupSheet(context, ref),
            ),
            _ProfileSettingRow(
              title: '清空数据',
              subtitle: '删除本地车辆、项目和记录',
              trailingLabel: '清空',
              onTap: () => _clearAllData(context, ref),
            ),
            _ProfileSettingRow(
              title: '手动日期',
              subtitle: manualDate.when(
                loading: () => '读取中',
                error: (error, stackTrace) => '读取失败',
                data: (value) => value == null ? '关闭 · 使用系统日期' : '开启 · $value',
              ),
              trailingLabel: '设置',
              onTap: () => _showManualDateSheet(context, ref),
            ),
            _ThemeModeSettingRow(
              mode: themeMode.maybeWhen(
                data: (value) => value,
                orElse: () => ThemeMode.system,
              ),
              onChanged: (mode) => _setThemeMode(context, ref, mode),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileSettingRow extends StatelessWidget {
  const _ProfileSettingRow({
    required this.title,
    required this.subtitle,
    required this.trailingLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String trailingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.line),
              borderRadius: BorderRadius.circular(tokens.radiusLarge),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(tokens.radiusSmall),
                    border: Border.all(color: tokens.line),
                  ),
                  child: Text(
                    trailingLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: tokens.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeModeSettingRow extends StatelessWidget {
  const _ThemeModeSettingRow({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          LunioSegmentedControl(
            values: const ['跟随系统', '浅色', '深色'],
            selectedIndex: switch (mode) {
              ThemeMode.light => 1,
              ThemeMode.dark => 2,
              ThemeMode.system => 0,
            },
            onSelected: (index) {
              onChanged(switch (index) {
                1 => ThemeMode.light,
                2 => ThemeMode.dark,
                _ => ThemeMode.system,
              });
            },
          ),
        ],
      ),
    );
  }
}

class _VehicleList extends StatelessWidget {
  const _VehicleList({
    required this.cars,
    required this.appliedCarId,
    required this.onAdd,
    required this.onEdit,
    required this.onApply,
    required this.onDelete,
  });

  final List<Car> cars;
  final int? appliedCarId;
  final VoidCallback onAdd;
  final ValueChanged<Car> onEdit;
  final ValueChanged<int> onApply;
  final ValueChanged<Car> onDelete;

  @override
  Widget build(BuildContext context) {
    if (cars.isEmpty) {
      return _EmptyVehicleCard(onAdd: onAdd);
    }
    return Column(
      children: [
        for (final car in cars) ...[
          LunioCard(
            backgroundColor: car.id == appliedCarId
                ? const Color(0xfff5fbf4)
                : null,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${car.brand} ${car.model}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              if (car.id == appliedCarId)
                                const LunioStatusBadge(
                                  label: '当前',
                                  tone: LunioStatusTone.normal,
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_formatNumber(car.currentMileageKm)} km · 上路 ${car.roadDate}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const _CarVisual(),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SmallActionButton(
                      label: car.id == appliedCarId ? '已应用' : '应用',
                      onPressed: car.id == null
                          ? () {}
                          : () => onApply(car.id!),
                    ),
                    const SizedBox(width: 8),
                    _SmallActionButton(
                      label: '编辑',
                      onPressed: () => onEdit(car),
                    ),
                    const SizedBox(width: 8),
                    _SmallActionButton(
                      label: '删除',
                      danger: true,
                      onPressed: () => onDelete(car),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CarVisual extends StatelessWidget {
  const _CarVisual();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(70, 38), painter: _CarVisualPainter());
  }
}

class _CarVisualPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xff1c7c57), Color(0xff2459a6)],
      ).createShader(Offset.zero & size);
    final windowPaint = Paint()..color = const Color(0xffdcebe4);
    final wheelPaint = Paint()..color = const Color(0xff1b211c);
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(5, 12, 60, 18),
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(22),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );
    final window = RRect.fromRectAndCorners(
      Rect.fromLTWH(18, 7, 32, 18),
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    );
    canvas
      ..drawRRect(body, bodyPaint)
      ..drawRRect(window, windowPaint)
      ..drawCircle(const Offset(18, 32), 5, wheelPaint)
      ..drawCircle(const Offset(57, 32), 5, wheelPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EmptyVehicleCard extends StatelessWidget {
  const _EmptyVehicleCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('还没有车辆', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          Tooltip(
            message: '新增车辆',
            child: LunioPrimaryButton(label: '新增车辆', onPressed: onAdd),
          ),
        ],
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return LunioPage(
      title: title,
      children: const [Center(child: CircularProgressIndicator())],
    );
  }
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.title, required this.error});

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return LunioPage(
      title: title,
      children: [LunioCard(child: Text('加载失败：${_friendlyError(error)}'))],
    );
  }
}

class _AddCarForm extends StatefulWidget {
  const _AddCarForm({
    required this.vehicleModels,
    this.initialCar,
    required this.onSubmit,
  });

  final List<VehicleModel> vehicleModels;
  final Car? initialCar;
  final Future<void> Function(Car car) onSubmit;

  @override
  State<_AddCarForm> createState() => _AddCarFormState();
}

class _AddCarFormState extends State<_AddCarForm> {
  late String selectedBrand;
  late String selectedModel;
  late final TextEditingController mileageController;
  late LocalDate roadDate;
  String? errorText;
  bool saving = false;

  bool get isEditing => widget.initialCar != null;

  @override
  void initState() {
    super.initState();
    final initialCar = widget.initialCar;
    final options = widget.vehicleModels;
    selectedBrand = initialCar?.brand ?? options.first.brand;
    selectedModel = initialCar?.model ?? _modelsForBrand(selectedBrand).first;
    mileageController = TextEditingController(
      text: initialCar?.currentMileageKm.toString() ?? '10000',
    );
    roadDate = initialCar?.roadDate ?? LocalDate.fromDateTime(DateTime.now());
  }

  @override
  void dispose() {
    mileageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isEditing)
          LunioPickerTile(
            label: '品牌车型',
            value: '${widget.initialCar!.brand} ${widget.initialCar!.model}',
            enabled: false,
            onTap: null,
          )
        else
          _VehicleModelPicker(
            vehicleModels: widget.vehicleModels,
            selectedBrand: selectedBrand,
            selectedModel: selectedModel,
            enabled: !saving,
            onSelected: (brand, model) {
              setState(() {
                selectedBrand = brand;
                selectedModel = model;
              });
            },
          ),
        const SizedBox(height: 10),
        TextField(
          controller: mileageController,
          enabled: !saving,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '当前里程'),
        ),
        const SizedBox(height: 10),
        LunioPickerTile(
          label: '上路日期',
          value: _formatDateForUser(roadDate),
          enabled: !saving,
          onTap: _pickRoadDate,
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存车辆',
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<String> _modelsForBrand(String brand) {
    return widget.vehicleModels
        .where((model) => model.brand == brand)
        .map((model) => model.model)
        .toList();
  }

  Future<void> _pickRoadDate() async {
    final picked = await _showSimpleDatePicker(
      context,
      initialDate: roadDate,
      firstDate: const LocalDate(1990, 1, 1),
      lastDate: LocalDate.fromDateTime(
        DateTime.now().add(const Duration(days: 365)),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => roadDate = picked);
  }

  Future<void> _submit() async {
    final mileage = int.tryParse(mileageController.text);
    if (mileage == null || mileage < 0) {
      setState(() => errorText = '当前里程必须是非负整数');
      return;
    }
    final initialCar = widget.initialCar;
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(
        Car(
          id: initialCar?.id,
          brand: initialCar?.brand ?? selectedBrand,
          model: initialCar?.model ?? selectedModel,
          currentMileageKm: mileage,
          roadDate: roadDate,
          sync: SyncMetadata(
            status: isEditing
                ? SyncStatus.pendingUpdate
                : SyncStatus.pendingCreate,
            updatedAt: DateTime.now(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }
}

class _VehicleModelPicker extends StatelessWidget {
  const _VehicleModelPicker({
    required this.vehicleModels,
    required this.selectedBrand,
    required this.selectedModel,
    required this.enabled,
    required this.onSelected,
  });

  final List<VehicleModel> vehicleModels;
  final String selectedBrand;
  final String selectedModel;
  final bool enabled;
  final void Function(String brand, String model) onSelected;

  @override
  Widget build(BuildContext context) {
    return LunioPickerTile(
      label: '品牌车型',
      value: '$selectedBrand $selectedModel',
      enabled: enabled,
      onTap: () async {
        final value = await _showVehicleModelPickerSheet(
          context,
          vehicleModels: vehicleModels,
          selectedBrand: selectedBrand,
          selectedModel: selectedModel,
        );
        if (value != null) {
          onSelected(value.$1, value.$2);
        }
      },
    );
  }
}

Future<(String, String)?> _showVehicleModelPickerSheet(
  BuildContext context, {
  required List<VehicleModel> vehicleModels,
  required String selectedBrand,
  required String selectedModel,
}) {
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) => _PrototypeSheetFrame(
      title: '选择车型',
      subtitle: '选择车辆品牌和车型，默认保养项目会随车型创建',
      heightFactor: 0.72,
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
      scrollable: false,
      child: _VehicleModelPickerSheet(
        vehicleModels: vehicleModels,
        selectedBrand: selectedBrand,
        selectedModel: selectedModel,
      ),
    ),
  );
}

class _VehicleModelPickerSheet extends StatefulWidget {
  const _VehicleModelPickerSheet({
    required this.vehicleModels,
    required this.selectedBrand,
    required this.selectedModel,
  });

  final List<VehicleModel> vehicleModels;
  final String selectedBrand;
  final String selectedModel;

  @override
  State<_VehicleModelPickerSheet> createState() =>
      _VehicleModelPickerSheetState();
}

class _VehicleModelPickerSheetState extends State<_VehicleModelPickerSheet> {
  final searchController = TextEditingController();
  late String selectedBrand;

  @override
  void initState() {
    super.initState();
    selectedBrand = widget.selectedBrand;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final keyword = searchController.text.trim();
    final filteredModels = keyword.isEmpty
        ? widget.vehicleModels
        : widget.vehicleModels
              .where(
                (model) => '${model.brand}${model.model}'.contains(keyword),
              )
              .toList();
    final brands = <String>[];
    for (final model in filteredModels) {
      if (!brands.contains(model.brand)) {
        brands.add(model.brand);
      }
    }
    if (!brands.contains(selectedBrand) && brands.isNotEmpty) {
      selectedBrand = brands.first;
    }
    final models = filteredModels
        .where((model) => model.brand == selectedBrand)
        .toList();
    return Column(
      children: [
        TextField(
          controller: searchController,
          decoration: const InputDecoration(
            labelText: '搜索品牌或车型',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: tokens.surface2,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.line),
          ),
          child: brands.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配车型',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 124,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: brands.length,
                        itemBuilder: (context, index) {
                          final brand = brands[index];
                          return _PickerOption(
                            label: brand,
                            selected: brand == selectedBrand,
                            enabled: true,
                            onTap: () => setState(() {
                              selectedBrand = brand;
                            }),
                          );
                        },
                      ),
                    ),
                    Container(width: 1, color: tokens.line),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final model = models[index];
                          final selected =
                              model.brand == widget.selectedBrand &&
                              model.model == widget.selectedModel;
                          return _PickerOption(
                            label: model.model,
                            selected: selected,
                            enabled: true,
                            onTap: () => Navigator.of(
                              context,
                            ).pop((model.brand, model.model)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      child: Container(
        height: 42,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected ? tokens.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? tokens.primary : tokens.muted,
          ),
        ),
      ),
    );
  }
}

void _showAddCarSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: '添加车辆',
        subtitle: '同一品牌车型当前只允许添加一辆',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: Consumer(
          builder: (context, ref, child) {
            final vehicleModels = ref.watch(vehicleModelsProvider);
            return vehicleModels.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  LunioInlineMessage(message: '车型加载失败，请稍后重试'),
              data: (models) {
                if (models.isEmpty) {
                  return const LunioInlineMessage(message: '暂无可选车型');
                }
                return _AddCarForm(
                  vehicleModels: models,
                  onSubmit: (car) async {
                    final repository = ref.read(lunioRepositoryProvider);
                    await repository.ensureBootstrapData();
                    await repository.createCarWithDefaultItems(car);
                    invalidateVehicleProviders(ref);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      _showToast(context, '车辆已保存');
                    }
                  },
                );
              },
            );
          },
        ),
      );
    },
  );
}

void _showEditCarSheet(BuildContext context, WidgetRef ref, Car car) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: '编辑车辆',
        subtitle: '品牌车型保持稳定，可更新当前里程和上路日期',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: Consumer(
          builder: (context, ref, child) {
            final vehicleModels = ref.watch(vehicleModelsProvider);
            return vehicleModels.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  LunioInlineMessage(message: '车型加载失败，请稍后重试'),
              data: (models) => _AddCarForm(
                vehicleModels: models.isEmpty
                    ? [
                        VehicleModel(
                          brand: car.brand,
                          model: car.model,
                          sortOrder: 0,
                          sync: SyncMetadata(
                            status: SyncStatus.synced,
                            updatedAt: DateTime.now(),
                          ),
                        ),
                      ]
                    : models,
                initialCar: car,
                onSubmit: (updatedCar) async {
                  await ref.read(lunioRepositoryProvider).updateCar(updatedCar);
                  invalidateVehicleProviders(ref);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    _showToast(context, '车辆已更新');
                  }
                },
              ),
            );
          },
        ),
      );
    },
  );
}

void _showVehicleSwitcher(BuildContext context, WidgetRef ref) {
  final cars = ref
      .read(carsProvider)
      .maybeWhen(data: (value) => value, orElse: () => const <Car>[]);
  final appliedCarId = ref
      .read(appliedCarProvider)
      .maybeWhen(data: (value) => value?.id, orElse: () => null);
  if (cars.length <= 1) {
    _showToast(context, cars.isEmpty ? '请先新增车辆' : '当前只有一辆车');
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: '选择应用车辆',
        subtitle: '提醒、记录和新增保养记录会跟随当前车辆',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final car in cars) ...[
              _SwitchCarCard(
                car: car,
                selected: car.id == appliedCarId,
                onTap: car.id == null
                    ? null
                    : () async {
                        await _applyCar(context, ref, car.id!);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
    },
  );
}

class _SwitchCarCard extends StatelessWidget {
  const _SwitchCarCard({
    required this.car,
    required this.selected,
    required this.onTap,
  });

  final Car car;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Material(
      color: selected ? const Color(0xfff5fbf4) : tokens.surface,
      borderRadius: BorderRadius.circular(tokens.radiusLarge),
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: selected ? tokens.primary : tokens.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${car.brand} ${car.model}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_formatNumber(car.currentMileageKm)} km · ${selected ? "当前应用" : "点击切换"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const _CarVisual(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceRecordForm extends StatefulWidget {
  const _MaintenanceRecordForm({
    required this.car,
    required this.items,
    required this.initialDate,
    this.record,
    required this.onSubmit,
  });

  final Car car;
  final List<MaintenanceItem> items;
  final LocalDate initialDate;
  final MaintenanceRecord? record;
  final Future<void> Function(MaintenanceRecord record) onSubmit;

  @override
  State<_MaintenanceRecordForm> createState() => _MaintenanceRecordFormState();
}

class _MaintenanceRecordFormState extends State<_MaintenanceRecordForm> {
  late LocalDate recordDate;
  late final TextEditingController mileageController;
  late final TextEditingController costController;
  late final TextEditingController noteController;
  late final Set<int> selectedItemIds;
  bool saving = false;
  String? errorText;

  bool get isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    recordDate = record?.date ?? widget.initialDate;
    mileageController = TextEditingController(
      text: (record?.mileageKm ?? widget.car.currentMileageKm).toString(),
    );
    costController = TextEditingController(
      text: record == null
          ? '0.00'
          : (record.costCents / 100).toStringAsFixed(2),
    );
    noteController = TextEditingController(text: record?.note ?? '');
    selectedItemIds = {...?record?.itemIds};
  }

  @override
  void dispose() {
    mileageController.dispose();
    costController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableItems = widget.record == null
        ? widget.items.where((item) => item.enabled).toList()
        : widget.items
              .where(
                (item) => item.enabled || selectedItemIds.contains(item.id),
              )
              .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LunioPickerTile(
          label: '保养日期',
          value: _formatDateForUser(recordDate),
          enabled: !saving,
          onTap: _pickRecordDate,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: mileageController,
                enabled: !saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: '保养里程'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: costController,
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '费用'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: noteController,
          enabled: !saving,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        const SizedBox(height: 12),
        Text('保养项目', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in availableItems)
              _ChoiceChipButton(
                label: item.enabled ? item.name : '${item.name}（已禁用）',
                selected: item.id != null && selectedItemIds.contains(item.id),
                enabled: !saving && item.id != null,
                onTap: () {
                  setState(() {
                    if (selectedItemIds.contains(item.id)) {
                      selectedItemIds.remove(item.id);
                    } else {
                      selectedItemIds.add(item.id!);
                    }
                  });
                },
              ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存记录',
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final mileage = int.tryParse(mileageController.text);
    final cost = double.tryParse(costController.text);
    if (mileage == null || mileage < 0) {
      setState(() => errorText = '保养里程必须是非负整数');
      return;
    }
    if (cost == null || cost < 0) {
      setState(() => errorText = '费用必须是非负数字');
      return;
    }
    if (selectedItemIds.isEmpty) {
      setState(() => errorText = '至少选择一个保养项目');
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(
        MaintenanceRecord(
          id: widget.record?.id,
          carId: widget.car.id!,
          date: recordDate,
          itemIds: selectedItemIds.toList(),
          costCents: (cost * 100).round(),
          mileageKm: mileage,
          note: noteController.text.trim().isEmpty
              ? null
              : noteController.text.trim(),
          sync: SyncMetadata(
            status: isEditing
                ? SyncStatus.pendingUpdate
                : SyncStatus.pendingCreate,
            updatedAt: DateTime.now(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }

  Future<void> _pickRecordDate() async {
    final picked = await _showSimpleDatePicker(
      context,
      initialDate: recordDate,
      firstDate: widget.car.roadDate,
      lastDate: LocalDate.fromDateTime(
        DateTime.now().add(const Duration(days: 365)),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => recordDate = picked);
  }
}

Future<void> _showMaintenanceRecordFormSheet(
  BuildContext context,
  WidgetRef ref, {
  MaintenanceRecord? record,
}) async {
  final car = await ref.read(appliedCarProvider.future);
  final items = await ref.read(appliedCarMaintenanceItemsProvider.future);
  final today = await ref.read(effectiveTodayProvider.future);
  if (!context.mounted) {
    return;
  }
  if (car?.id == null) {
    _showToast(context, '请先新增车辆');
    return;
  }
  if (items
      .where(
        (item) => item.enabled || record?.itemIds.contains(item.id) == true,
      )
      .isEmpty) {
    _showToast(context, '请先配置可用保养项目');
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: record == null ? '新增保养记录' : '编辑保养记录',
        subtitle: '保存前确认项目和里程，保存后会同步更新提醒进度',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: _MaintenanceRecordForm(
          car: car!,
          items: items,
          initialDate: today,
          record: record,
          onSubmit: (value) async {
            final repository = ref.read(lunioRepositoryProvider);
            if (value.id == null) {
              await repository.saveMaintenanceRecord(value);
            } else {
              await repository.updateMaintenanceRecord(value);
            }
            invalidateVehicleProviders(ref);
            if (context.mounted) {
              Navigator.of(context).pop();
              _showToast(context, '保养记录已保存');
            }
          },
        ),
      );
    },
  );
}

Future<void> _deleteMaintenanceRecord(
  BuildContext context,
  WidgetRef ref,
  MaintenanceRecord record,
) async {
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '删除保养记录',
    message: '确定删除 ${record.date} 的保养记录？',
    confirmLabel: '删除',
  );
  if (confirmed != true || record.id == null) {
    return;
  }
  await ref.read(lunioRepositoryProvider).deleteMaintenanceRecord(record.id!);
  invalidateVehicleProviders(ref);
  if (context.mounted) {
    _showToast(context, '保养记录已删除');
  }
}

void _showMaintenanceItemsSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: '保养项目',
        subtitle: '项目名称可变，默认项目用稳定映射保留历史记录',
        heightFactor: 0.82,
        scrollable: false,
        trailing: Consumer(
          builder: (context, ref, child) {
            final car = ref
                .watch(appliedCarProvider)
                .maybeWhen(data: (value) => value, orElse: () => null);
            return LunioIconButton(
              icon: Icons.add,
              tooltip: '新增项目',
              onPressed: car == null
                  ? null
                  : () => _showMaintenanceItemFormSheet(
                      context,
                      ref,
                      carId: car.id!,
                    ),
            );
          },
        ),
        child: Consumer(
          builder: (context, ref, child) {
            final car = ref
                .watch(appliedCarProvider)
                .maybeWhen(data: (value) => value, orElse: () => null);
            final items = ref.watch(appliedCarMaintenanceItemsProvider);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (car != null) ...[
                  _ItemPills(
                    labels: ['${car.brand} ${car.model}', '关闭后不出现在新增记录里'],
                  ),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: items.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) =>
                        Text('加载失败：${_friendlyError(error)}'),
                    data: (value) => _MaintenanceItemList(
                      items: value,
                      onEdit: (item) => _showMaintenanceItemFormSheet(
                        context,
                        ref,
                        carId: item.carsId,
                        item: item,
                      ),
                      onToggle: (item) =>
                          _toggleMaintenanceItem(context, ref, item),
                      onDelete: (item) =>
                          _deleteMaintenanceItem(context, ref, item),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

class _MaintenanceItemList extends StatelessWidget {
  const _MaintenanceItemList({
    required this.items,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final List<MaintenanceItem> items;
  final ValueChanged<MaintenanceItem> onEdit;
  final ValueChanged<MaintenanceItem> onToggle;
  final ValueChanged<MaintenanceItem> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text('暂无保养项目', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return _MaintenanceItemCard(
          item: item,
          onEdit: () => onEdit(item),
          onToggle: () => onToggle(item),
          onDelete: item.isDefault ? null : () => onDelete(item),
        );
      },
    );
  }
}

class _MaintenanceItemCard extends StatelessWidget {
  const _MaintenanceItemCard({
    required this.item,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final MaintenanceItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    LunioStatusBadge(
                      label: item.isDefault ? '默认' : '自定义',
                      tone: LunioStatusTone.normal,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _itemRuleText(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: item.enabled,
            onChanged: (_) => onToggle(),
            activeThumbColor: tokens.primary,
          ),
          IconButton(
            tooltip: '编辑',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: '删除',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }
}

class _MaintenanceItemForm extends StatefulWidget {
  const _MaintenanceItemForm({
    required this.carId,
    this.item,
    required this.onSubmit,
  });

  final int carId;
  final MaintenanceItem? item;
  final Future<void> Function(MaintenanceItem item) onSubmit;

  @override
  State<_MaintenanceItemForm> createState() => _MaintenanceItemFormState();
}

class _MaintenanceItemFormState extends State<_MaintenanceItemForm> {
  late final TextEditingController nameController;
  late final TextEditingController mileageController;
  late final TextEditingController monthsController;
  late final TextEditingController normalLimitController;
  late final TextEditingController overdueLimitController;
  bool remindByMileage = true;
  bool remindByTime = true;
  bool enabled = true;
  bool saving = false;
  String? errorText;

  bool get isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    nameController = TextEditingController(text: item?.name ?? '');
    mileageController = TextEditingController(
      text: (item?.mileageIntervalKm ?? 5000).toString(),
    );
    monthsController = TextEditingController(
      text: (item?.timeIntervalMonths ?? 6).toString(),
    );
    normalLimitController = TextEditingController(
      text: (item?.notOverdueUpperLimit ?? 100).toStringAsFixed(0),
    );
    overdueLimitController = TextEditingController(
      text: (item?.overdueUpperLimit ?? 125).toStringAsFixed(0),
    );
    remindByMileage = item?.remindByMileage ?? true;
    remindByTime = item?.remindByTime ?? true;
    enabled = item?.enabled ?? true;
  }

  @override
  void dispose() {
    nameController.dispose();
    mileageController.dispose();
    monthsController.dispose();
    normalLimitController.dispose();
    overdueLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameController,
          enabled: !saving && !(widget.item?.isDefault ?? false),
          decoration: const InputDecoration(labelText: '项目名称'),
        ),
        const SizedBox(height: 10),
        _FormSwitchRow(
          title: '按里程提醒',
          value: remindByMileage,
          onChanged: saving
              ? null
              : (value) => setState(() => remindByMileage = value),
        ),
        if (remindByMileage)
          TextField(
            controller: mileageController,
            enabled: !saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '里程间隔 km'),
          ),
        const SizedBox(height: 10),
        _FormSwitchRow(
          title: '按时间提醒',
          value: remindByTime,
          onChanged: saving
              ? null
              : (value) => setState(() => remindByTime = value),
        ),
        if (remindByTime)
          TextField(
            controller: monthsController,
            enabled: !saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '时间间隔 月'),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: normalLimitController,
                enabled: !saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: '正常上限'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: overdueLimitController,
                enabled: !saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: '超期上限'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _FormSwitchRow(
          title: '启用项目',
          value: enabled,
          onChanged: saving ? null : (value) => setState(() => enabled = value),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存项目',
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = nameController.text.trim();
    final mileageInterval = int.tryParse(mileageController.text);
    final timeInterval = int.tryParse(monthsController.text);
    final normalLimit = double.tryParse(normalLimitController.text);
    final overdueLimit = double.tryParse(overdueLimitController.text);
    if (name.isEmpty) {
      setState(() => errorText = '项目名称不能为空');
      return;
    }
    if (!remindByMileage && !remindByTime) {
      setState(() => errorText = '至少选择一种提醒方式');
      return;
    }
    if (remindByMileage && (mileageInterval == null || mileageInterval <= 0)) {
      setState(() => errorText = '里程间隔必须大于 0');
      return;
    }
    if (remindByTime && (timeInterval == null || timeInterval <= 0)) {
      setState(() => errorText = '时间间隔必须大于 0');
      return;
    }
    if (normalLimit == null ||
        overdueLimit == null ||
        normalLimit >= overdueLimit) {
      setState(() => errorText = '超期值上限必须大于未超期值上限');
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    final item = widget.item;
    try {
      await widget.onSubmit(
        MaintenanceItem(
          id: item?.id,
          carsId: widget.carId,
          name: item?.isDefault == true ? item!.name : name,
          isDefault: item?.isDefault ?? false,
          enabled: enabled,
          remindByMileage: remindByMileage,
          remindByTime: remindByTime,
          mileageIntervalKm: remindByMileage ? mileageInterval : null,
          timeIntervalMonths: remindByTime ? timeInterval : null,
          notOverdueUpperLimit: normalLimit,
          overdueUpperLimit: overdueLimit,
          sortOrder: item?.sortOrder ?? 999,
          sync: SyncMetadata(
            status: isEditing
                ? SyncStatus.pendingUpdate
                : SyncStatus.pendingCreate,
            updatedAt: DateTime.now(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }
}

class _FormSwitchRow extends StatelessWidget {
  const _FormSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.labelLarge),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: tokens.primary,
          ),
        ],
      ),
    );
  }
}

void _showMaintenanceItemFormSheet(
  BuildContext context,
  WidgetRef ref, {
  required int carId,
  MaintenanceItem? item,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: item == null ? '新增保养项目' : '编辑保养项目',
        subtitle: item?.isDefault == true
            ? '默认项目名称保持稳定，可调整提醒规则和启用状态'
            : '自定义项目没有历史记录时可删除',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: _MaintenanceItemForm(
          carId: carId,
          item: item,
          onSubmit: (value) async {
            final repository = ref.read(lunioRepositoryProvider);
            if (value.id == null) {
              await repository.saveMaintenanceItem(value);
            } else {
              await repository.updateMaintenanceItem(value);
            }
            invalidateVehicleProviders(ref);
            if (context.mounted) {
              Navigator.of(context).pop();
              _showToast(context, '保养项目已保存');
            }
          },
        ),
      );
    },
  );
}

Future<void> _toggleMaintenanceItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceItem item,
) async {
  final nextEnabled = !item.enabled;
  try {
    await ref
        .read(lunioRepositoryProvider)
        .setMaintenanceItemEnabled(
          itemId: item.id!,
          enabled: nextEnabled,
          sync: SyncMetadata(
            status: SyncStatus.pendingUpdate,
            updatedAt: DateTime.now(),
          ),
        );
    invalidateVehicleProviders(ref);
    if (context.mounted) {
      _showToast(context, nextEnabled ? '项目已启用' : '项目已禁用');
    }
  } catch (error) {
    if (context.mounted) {
      _showToast(context, _friendlyError(error));
    }
  }
}

Future<void> _deleteMaintenanceItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceItem item,
) async {
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '删除保养项目',
    message: '确定删除 ${item.name}？有历史记录的项目不能删除。',
    confirmLabel: '删除',
  );
  if (confirmed != true || item.id == null) {
    return;
  }
  try {
    await ref.read(lunioRepositoryProvider).deleteMaintenanceItem(item.id!);
    invalidateVehicleProviders(ref);
    if (context.mounted) {
      _showToast(context, '保养项目已删除');
    }
  } catch (error) {
    if (context.mounted) {
      _showToast(context, _friendlyError(error));
    }
  }
}

Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
  try {
    final payload = await ref
        .read(lunioRepositoryProvider)
        .exportBackupPayload();
    const codec = BackupCodec();
    final json = codec.encode(payload);
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/lunio-backup-${LocalDate.fromDateTime(DateTime.now())}.json',
    );
    await file.writeAsString(json);
    if (context.mounted) {
      _showBackupResultSheet(context, file.path, json);
    }
  } catch (error) {
    if (context.mounted) {
      _showToast(context, '备份失败：$error');
    }
  }
}

void _showBackupResultSheet(BuildContext context, String path, String json) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('数据备份', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '已生成 schemaVersion 1 备份文件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              LunioCard(
                child: SelectableText(
                  path,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: json),
                  readOnly: true,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(labelText: '备份 JSON'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LunioSecondaryButton(
                      label: '复制 JSON',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: json));
                        if (context.mounted) {
                          _showToast(context, '备份 JSON 已复制');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LunioPrimaryButton(
                      label: '分享文件',
                      onPressed: () async {
                        try {
                          await NativeFiles.shareFile(path);
                        } catch (error) {
                          if (context.mounted) {
                            _showToast(context, '分享失败：$error');
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showRestoreBackupSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: _RestoreBackupForm(
          onSubmit: (json) async {
            const codec = BackupCodec();
            final payload = codec.decode(json);
            await ref
                .read(lunioRepositoryProvider)
                .restoreBackupPayload(payload);
            invalidateAllAppDataProviders(ref);
            if (context.mounted) {
              Navigator.of(context).pop();
              _showToast(context, '数据已恢复');
            }
          },
        ),
      );
    },
  );
}

class _RestoreBackupForm extends StatefulWidget {
  const _RestoreBackupForm({required this.onSubmit});

  final Future<void> Function(String json) onSubmit;

  @override
  State<_RestoreBackupForm> createState() => _RestoreBackupFormState();
}

class _RestoreBackupFormState extends State<_RestoreBackupForm> {
  final controller = TextEditingController();
  bool restoring = false;
  String? errorText;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('数据恢复', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '粘贴 schemaVersion 1 备份 JSON。恢复会替换当前本地数据，失败时保持原数据。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          LunioSecondaryButton(
            label: '选择 JSON 文件',
            onPressed: restoring ? null : _pickFile,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: !restoring,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(labelText: '备份 JSON'),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              errorText!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.red),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: LunioSecondaryButton(
                  label: '取消',
                  onPressed: restoring
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LunioPrimaryButton(
                  label: restoring ? '恢复中' : '恢复数据',
                  onPressed: restoring ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (controller.text.trim().isEmpty) {
      setState(() => errorText = '备份 JSON 不能为空');
      return;
    }
    setState(() {
      restoring = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(controller.text.trim());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        restoring = false;
        errorText = '恢复失败：$error';
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final json = await NativeFiles.pickJsonFile();
      if (!mounted || json == null) {
        return;
      }
      controller.text = json;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => errorText = '选择文件失败：$error');
    }
  }
}

Future<void> _clearAllData(BuildContext context, WidgetRef ref) async {
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '清空数据',
    message: '确定清空本地车辆、保养项目、保养记录和偏好？该操作不可撤销。',
    confirmLabel: '清空',
  );
  if (confirmed != true) {
    return;
  }
  await ref.read(lunioRepositoryProvider).clearAllData();
  invalidateAllAppDataProviders(ref);
  if (context.mounted) {
    _showToast(context, '本地数据已清空');
  }
}

void _showManualDateSheet(BuildContext context, WidgetRef ref) {
  final initialDate = ref
      .read(manualDatePreferenceProvider)
      .maybeWhen(data: (value) => value, orElse: () => null);
  final fallbackDate = ref
      .read(effectiveTodayProvider)
      .maybeWhen(
        data: (value) => value,
        orElse: () => LocalDate.fromDateTime(DateTime.now()),
      );
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: _ManualDateForm(
          initialDate: initialDate,
          fallbackDate: fallbackDate,
          onSubmit: (date) async {
            final repository = ref.read(lunioRepositoryProvider);
            if (date == null) {
              await repository.setPreferenceValue('manualDateEnabled', 'false');
              await repository.setPreferenceValue('manualDate', null);
            } else {
              await repository.setPreferenceValue('manualDateEnabled', 'true');
              await repository.setPreferenceValue(
                'manualDate',
                date.toString(),
              );
            }
            invalidatePreferenceProviders(ref);
            if (context.mounted) {
              Navigator.of(context).pop();
              _showToast(context, date == null ? '手动日期已关闭' : '手动日期已保存');
            }
          },
        ),
      );
    },
  );
}

class _ManualDateForm extends StatefulWidget {
  const _ManualDateForm({
    required this.initialDate,
    required this.fallbackDate,
    required this.onSubmit,
  });

  final LocalDate? initialDate;
  final LocalDate fallbackDate;
  final Future<void> Function(LocalDate? date) onSubmit;

  @override
  State<_ManualDateForm> createState() => _ManualDateFormState();
}

class _ManualDateFormState extends State<_ManualDateForm> {
  late LocalDate selectedDate;
  late bool enabled;
  bool saving = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    enabled = widget.initialDate != null;
    selectedDate = widget.initialDate ?? widget.fallbackDate;
  }

  @override
  void dispose() => super.dispose();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('手动日期', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '开启后，保养提醒里的“今天”会使用该日期。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启用手动日期'),
          value: enabled,
          onChanged: saving ? null : (value) => setState(() => enabled = value),
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          LunioPickerTile(
            label: '日期',
            value: _formatDateForUser(selectedDate),
            enabled: !saving,
            onTap: _pickDate,
          ),
        ],
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存日期',
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final date = enabled ? selectedDate : null;
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(date);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await _showSimpleDatePicker(
      context,
      initialDate: selectedDate,
      firstDate: const LocalDate(1990, 1, 1),
      lastDate: LocalDate.fromDateTime(
        DateTime.now().add(const Duration(days: 3650)),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => selectedDate = picked);
  }
}

Future<LocalDate?> _showSimpleDatePicker(
  BuildContext context, {
  required LocalDate initialDate,
  required LocalDate firstDate,
  required LocalDate lastDate,
}) {
  return showModalBottomSheet<LocalDate>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      child: _SimpleDatePicker(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    ),
  );
}

class _SimpleDatePicker extends StatefulWidget {
  const _SimpleDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final LocalDate initialDate;
  final LocalDate firstDate;
  final LocalDate lastDate;

  @override
  State<_SimpleDatePicker> createState() => _SimpleDatePickerState();
}

class _SimpleDatePickerState extends State<_SimpleDatePicker> {
  late LocalDate selectedDate;
  late int visibleYear;
  late int visibleMonth;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate;
    visibleYear = selectedDate.year;
    visibleMonth = selectedDate.month;
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(visibleYear, visibleMonth, 1).weekday;
    final daysInMonth = DateTime(visibleYear, visibleMonth + 1, 0).day;
    final leadingBlankCount = firstWeekday - 1;
    final cells = leadingBlankCount + daysInMonth;
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return LunioSheetScaffold(
      title: '选择日期',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _DateSelectBox<int>(
                  value: visibleYear,
                  items: [
                    for (
                      var year = widget.firstDate.year;
                      year <= widget.lastDate.year;
                      year++
                    )
                      DropdownMenuItem(value: year, child: Text('$year年')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      visibleYear = value;
                      final months = _validMonthsForYear(value);
                      if (!months.contains(visibleMonth)) {
                        visibleMonth = months.first;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateSelectBox<int>(
                  value: visibleMonth,
                  items: [
                    for (final month in _validMonthsForYear(visibleYear))
                      DropdownMenuItem(value: month, child: Text('$month月')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => visibleMonth = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '上个月',
                    onPressed: _canGoPreviousMonth() ? _previousMonth : null,
                    style: IconButton.styleFrom(
                      backgroundColor: tokens.surface2,
                      foregroundColor: tokens.ink,
                    ),
                  ),
                ),
              ),
              Text(
                '$visibleYear年$visibleMonth月',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '下个月',
                    onPressed: _canGoNextMonth() ? _nextMonth : null,
                    style: IconButton.styleFrom(
                      backgroundColor: tokens.surface2,
                      foregroundColor: tokens.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              for (var index = 0; index < cells; index++)
                if (index < leadingBlankCount)
                  const SizedBox.shrink()
                else
                  _DateCell(
                    date: LocalDate(
                      visibleYear,
                      visibleMonth,
                      index - leadingBlankCount + 1,
                    ),
                    selectedDate: selectedDate,
                    firstDate: widget.firstDate,
                    lastDate: widget.lastDate,
                    onSelected: (date) => setState(() => selectedDate = date),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: LunioSecondaryButton(
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LunioPrimaryButton(
                  label: '确定',
                  onPressed: () => Navigator.of(context).pop(selectedDate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _canGoPreviousMonth() {
    return visibleYear > widget.firstDate.year ||
        (visibleYear == widget.firstDate.year &&
            visibleMonth > widget.firstDate.month);
  }

  bool _canGoNextMonth() {
    return visibleYear < widget.lastDate.year ||
        (visibleYear == widget.lastDate.year &&
            visibleMonth < widget.lastDate.month);
  }

  void _previousMonth() {
    setState(() {
      if (visibleMonth == 1) {
        visibleYear -= 1;
        visibleMonth = 12;
      } else {
        visibleMonth -= 1;
      }
    });
  }

  void _nextMonth() {
    setState(() {
      if (visibleMonth == 12) {
        visibleYear += 1;
        visibleMonth = 1;
      } else {
        visibleMonth += 1;
      }
    });
  }

  List<int> _validMonthsForYear(int year) {
    final firstMonth = year == widget.firstDate.year
        ? widget.firstDate.month
        : 1;
    final lastMonth = year == widget.lastDate.year ? widget.lastDate.month : 12;
    return [for (var month = firstMonth; month <= lastMonth; month++) month];
  }
}

class _DateSelectBox<T> extends StatelessWidget {
  const _DateSelectBox({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          dropdownColor: tokens.surface,
        ),
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.date,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.onSelected,
  });

  final LocalDate date;
  final LocalDate selectedDate;
  final LocalDate firstDate;
  final LocalDate lastDate;
  final ValueChanged<LocalDate> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final selected = date == selectedDate;
    final enabled =
        date.compareTo(firstDate) >= 0 && date.compareTo(lastDate) <= 0;
    return InkWell(
      onTap: enabled ? () => onSelected(date) : null,
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
        ),
        child: Text(
          '${date.day}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? Colors.white
                : enabled
                ? tokens.ink
                : tokens.subtle.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class _ReminderViewData {
  const _ReminderViewData({
    required this.item,
    required this.progress,
    required this.latestRecord,
    required this.currentMileageKm,
    required this.roadDate,
  });

  final MaintenanceItem item;
  final ReminderProgress progress;
  final MaintenanceRecord? latestRecord;
  final int currentMileageKm;
  final LocalDate roadDate;

  String get title => item.name;

  String get percentText => _formatPercent(progress.percent);

  double get progressValue {
    final cap = item.overdueUpperLimit <= 0 ? 125 : item.overdueUpperLimit;
    return (progress.percent / cap).clamp(0, 1).toDouble();
  }

  LunioStatusTone get tone {
    return switch (progress.status) {
      ReminderStatus.normal => LunioStatusTone.normal,
      ReminderStatus.warning => LunioStatusTone.warning,
      ReminderStatus.danger => LunioStatusTone.danger,
    };
  }

  String get badge {
    return switch (progress.status) {
      ReminderStatus.normal => '正常',
      ReminderStatus.warning => '将到期',
      ReminderStatus.danger => '已超期',
    };
  }

  String get detail {
    final record = latestRecord;
    return switch (progress.reason) {
      'mileage-no-history' =>
        '按里程计算，当前里程 ${_formatNumber(currentMileageKm)} / ${_formatNumber(item.mileageIntervalKm ?? 0)} km',
      'mileage' =>
        '按里程计算，上次 ${record?.date ?? '-'} · ${_formatNumber(record?.mileageKm ?? 0)} km',
      'time-no-history' =>
        '按时间计算，上路 $roadDate · ${item.timeIntervalMonths ?? 0} 个月',
      'time' =>
        '按时间计算，上次 ${record?.date ?? '-'} · ${item.timeIntervalMonths ?? 0} 个月',
      _ => '未达到提醒周期',
    };
  }
}

List<_ReminderViewData> _buildReminderRows({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final rows = <_ReminderViewData>[];
  for (final item in items.where((item) => item.enabled && item.id != null)) {
    final latestRecord = _latestRecordForItem(records, item.id!);
    final progress = MaintenanceRules.progressForItem(
      item: item,
      latestRecord: latestRecord,
      currentMileageKm: car.currentMileageKm,
      noHistoryBaselineDate: car.roadDate,
      today: today,
    );
    rows.add(
      _ReminderViewData(
        item: item,
        progress: progress,
        latestRecord: latestRecord,
        currentMileageKm: car.currentMileageKm,
        roadDate: car.roadDate,
      ),
    );
  }
  rows.sort((left, right) {
    final statusCompare = _statusRank(
      right.progress.status,
    ).compareTo(_statusRank(left.progress.status));
    if (statusCompare != 0) {
      return statusCompare;
    }
    final progressCompare = right.progress.percent.compareTo(
      left.progress.percent,
    );
    if (progressCompare != 0) {
      return progressCompare;
    }
    return left.item.sortOrder.compareTo(right.item.sortOrder);
  });
  return rows;
}

MaintenanceRecord? _latestRecordForItem(
  List<MaintenanceRecord> records,
  int itemId,
) {
  MaintenanceRecord? latest;
  for (final record in records) {
    if (!record.itemIds.contains(itemId)) {
      continue;
    }
    if (latest == null ||
        record.date.compareTo(latest.date) > 0 ||
        (record.date == latest.date && record.mileageKm > latest.mileageKm)) {
      latest = record;
    }
  }
  return latest;
}

int _statusRank(ReminderStatus status) {
  return switch (status) {
    ReminderStatus.normal => 0,
    ReminderStatus.warning => 1,
    ReminderStatus.danger => 2,
  };
}

String _mostUrgentText(
  AsyncValue<List<MaintenanceItem>> items,
  AsyncValue<List<MaintenanceRecord>> records,
  Car car,
  LocalDate today,
) {
  if (items.isLoading || records.isLoading) {
    return '计算中';
  }
  if (items.hasError || records.hasError) {
    return '加载失败';
  }
  final rows = _buildReminderRows(
    car: car,
    items: items.value ?? const [],
    records: records.value ?? const [],
    today: today,
  );
  if (rows.isEmpty) {
    return '无项目';
  }
  return '${rows.first.badge} ${rows.first.percentText}';
}

String _formatPercent(double percent) {
  return percent.round() > 999 ? '999%+' : '${percent.round()}%';
}

String _itemRuleText(MaintenanceItem item) {
  final rules = <String>[];
  if (item.remindByMileage) {
    rules.add('${_formatNumber(item.mileageIntervalKm ?? 0)} km');
  }
  if (item.remindByTime) {
    rules.add('${item.timeIntervalMonths ?? 0} 个月');
  }
  return [
    rules.join(' / '),
    '正常 < ${item.notOverdueUpperLimit.toStringAsFixed(0)}%',
    '将到期 < ${item.overdueUpperLimit.toStringAsFixed(0)}%',
  ].join(' · ');
}

List<String> _recordItemNameList(
  MaintenanceRecord record,
  List<MaintenanceItem> items,
) {
  return record.itemIds
      .map((id) => _itemById(items, id)?.name ?? '未知项目')
      .toList();
}

MaintenanceItem? _itemById(List<MaintenanceItem> items, int itemId) {
  for (final item in items) {
    if (item.id == itemId) {
      return item;
    }
  }
  return null;
}

String _formatMoney(int costCents) {
  return '¥${(costCents / 100).toStringAsFixed(2)}';
}

Future<void> _applyCar(BuildContext context, WidgetRef ref, int carId) async {
  await ref.read(lunioRepositoryProvider).setAppliedCarId(carId);
  invalidateVehicleProviders(ref);
  if (context.mounted) {
    _showToast(context, '当前车辆已切换');
  }
}

Future<void> _setThemeMode(
  BuildContext context,
  WidgetRef ref,
  ThemeMode mode,
) async {
  final value = switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
  await ref
      .read(lunioRepositoryProvider)
      .setPreferenceValue('themeMode', value);
  invalidatePreferenceProviders(ref);
  if (context.mounted) {
    _showToast(context, '主题已切换');
  }
}

Future<void> _deleteCar(BuildContext context, WidgetRef ref, Car car) async {
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '删除车辆',
    message: '确定删除 ${car.brand} ${car.model}？相关项目和记录会同步删除。',
    confirmLabel: '删除',
  );
  if (confirmed != true || car.id == null) {
    return;
  }
  await ref.read(lunioRepositoryProvider).deleteCar(car.id!);
  invalidateVehicleProviders(ref);
  if (context.mounted) {
    _showToast(context, '车辆已删除');
  }
}

Future<bool?> _showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 86, left: 18, right: 18),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusLarge),
                border: Border.all(color: tokens.line),
                boxShadow: [
                  BoxShadow(
                    color: tokens.ink.withValues(alpha: 0.12),
                    blurRadius: 36,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: LunioSecondaryButton(
                          label: '取消',
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LunioPrimaryButton(
                          label: confirmLabel,
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

void _dismissTransientUi(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  }
}

void _showToast(BuildContext context, String message) {
  final tokens = Theme.of(context).extension<LunioTokens>()!;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.check_circle_outline, color: tokens.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: tokens.surface,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 98),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        side: BorderSide(color: tokens.line),
      ),
    ),
  );
}

String _friendlyError(Object error) {
  final message = error.toString();
  if (message.contains('这辆车当天')) {
    return message.replaceFirst('Bad state: ', '');
  }
  if (message.contains('UNIQUE constraint') ||
      message.contains('SqliteException(2067')) {
    return '这条数据已经保存过了';
  }
  if (message.contains('At least one maintenance item must stay enabled')) {
    return '至少保留一个可用保养项目';
  }
  if (message.contains('Maintenance item has history records')) {
    return '已有保养记录的项目不能删除';
  }
  if (message.contains('Default maintenance items cannot be deleted')) {
    return '默认保养项目不能删除';
  }
  if (message.contains('contains missing items')) {
    return '选择的保养项目不存在，请重新选择';
  }
  if (message.contains('items from another car')) {
    return '保养项目不属于当前车辆，请重新选择';
  }
  return '操作失败，请稍后重试';
}

String _formatDateForUser(LocalDate date) {
  return '${date.year}年${date.month}月${date.day}日';
}

String _formatNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final fromEnd = text.length - i;
    buffer.write(text[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

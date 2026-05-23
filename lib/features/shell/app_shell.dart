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
              onPressed: () => _showMaintenanceRecordFormSheet(context, ref),
              tooltip: '新增保养记录',
              backgroundColor: tokens.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusLarge),
              ),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusXl),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.10),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusXl),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                switch (index) {
                  case 0:
                    context.go('/reminders');
                  case 1:
                    context.go('/records');
                  case 2:
                    context.go('/me');
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_repair_service_outlined),
                  selectedIcon: Icon(Icons.home_repair_service),
                  label: '提醒',
                ),
                NavigationDestination(
                  icon: Icon(Icons.format_list_bulleted_outlined),
                  selectedIcon: Icon(Icons.format_list_bulleted),
                  label: '记录',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '我的',
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
    final items = ref.watch(appliedCarMaintenanceItemsProvider);
    final records = ref.watch(appliedCarRecordsProvider);
    final today = ref.watch(effectiveTodayProvider);
    return appliedCar.when(
      loading: () => const _LoadingPage(title: '保养提醒'),
      error: (error, stackTrace) => _ErrorPage(title: '保养提醒', error: error),
      data: (car) => LunioPage(
        title: '保养提醒',
        subtitle: '当前车辆的到期项目优先展示',
        trailing: LunioIconButton(
          icon: Icons.swap_horiz,
          tooltip: '切换车辆',
          onPressed: () => _showVehicleSwitcher(context, ref),
        ),
        children: [
          if (car == null)
            _EmptyVehicleCard(onAdd: () => _showAddCarSheet(context, ref))
          else
            LunioHeroCard(
              title: '${car.brand} ${car.model}',
              subtitle: '当前应用车辆',
              actionLabel: '切换',
              onAction: () => _showVehicleSwitcher(context, ref),
              metrics: [
                LunioMetric(
                  label: '当前里程',
                  value: '${_formatNumber(car.currentMileageKm)} km',
                ),
                LunioMetric(
                  label: '最紧急',
                  value: today.when(
                    loading: () => '计算中',
                    error: (error, stackTrace) => '日期失败',
                    data: (value) =>
                        _mostUrgentText(items, records, car, value),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 18),
          if (car == null)
            Text(
              '新增车辆后会自动加载该车型默认保养项目。',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            today.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  LunioCard(child: Text('日期加载失败：$error')),
              data: (value) => _ReminderList(
                car: car,
                items: items,
                records: records,
                today: value,
              ),
            ),
        ],
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
      return LunioCard(child: Text('保养项目加载失败：${items.error}'));
    }
    if (records.hasError) {
      return LunioCard(child: Text('保养记录加载失败：${records.error}'));
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
      LunioStatusTone.normal => tokens.primary,
      LunioStatusTone.warning => tokens.warning,
      LunioStatusTone.danger => tokens.danger,
    };
    return LunioCard(
      child: Row(
        children: [
          SizedBox.square(
            dimension: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: row.progressValue,
                  strokeWidth: 6,
                  backgroundColor: tokens.surface2,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Text(
                  row.percentText,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
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
      subtitle: car == null ? '先新增车辆，再记录保养' : '${car.brand} ${car.model}',
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
        records.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => LunioCard(child: Text('记录加载失败：$error')),
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
                  '${_formatNumber(record.mileageKm)} km · ${_recordItemNames(record, items)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (record.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    record.note!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => onEdit(record),
                      child: const Text('编辑'),
                    ),
                    TextButton(
                      onPressed: () => onDelete(record),
                      child: const Text('删除'),
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
    final appliedCar = ref
        .watch(appliedCarProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    return LunioPage(
      title: '我的',
      subtitle: '车辆、备份和调试日期集中管理',
      trailing: LunioIconButton(
        icon: Icons.add,
        tooltip: '新增车辆',
        onPressed: () => _showAddCarSheet(context, ref),
      ),
      children: [
        _ProfileAction(
          icon: Icons.directions_car_outlined,
          title: '当前应用车辆',
          subtitle: appliedCar == null
              ? '未选择'
              : '${appliedCar.brand} ${appliedCar.model}',
          onTap: () => _showVehicleSwitcher(context, ref),
        ),
        const SizedBox(height: 12),
        _ProfileAction(
          icon: Icons.construction_outlined,
          title: '保养项目配置',
          subtitle: appliedCar == null ? '请先新增车辆' : '默认项目和自定义项目',
          onTap: appliedCar == null
              ? () => _showToast(context, '请先新增车辆')
              : () => _showMaintenanceItemsSheet(context, ref),
        ),
        const SizedBox(height: 12),
        cars.when(
          loading: () => const LunioCard(child: Text('车辆加载中...')),
          error: (error, stackTrace) => LunioCard(child: Text('车辆加载失败：$error')),
          data: (items) => _VehicleList(
            cars: items,
            appliedCarId: appliedCar?.id,
            onAdd: () => _showAddCarSheet(context, ref),
            onEdit: (car) => _showEditCarSheet(context, ref, car),
            onApply: (carId) => _applyCar(context, ref, carId),
            onDelete: (car) => _deleteCar(context, ref, car),
          ),
        ),
        const SizedBox(height: 12),
        _ProfileAction(
          icon: Icons.file_upload_outlined,
          title: '数据备份',
          subtitle: '导出 schemaVersion 1 JSON',
          onTap: () => _exportBackup(context, ref),
        ),
        const SizedBox(height: 12),
        _ProfileAction(
          icon: Icons.restore_page_outlined,
          title: '数据恢复',
          subtitle: '导入失败会完整回滚',
          onTap: () => _showRestoreBackupSheet(context, ref),
        ),
        const SizedBox(height: 12),
        _ProfileAction(
          icon: Icons.delete_sweep_outlined,
          title: '清空数据',
          subtitle: '删除本地车辆、项目、记录和偏好',
          onTap: () => _clearAllData(context, ref),
        ),
        const SizedBox(height: 12),
        _ProfileAction(
          icon: Icons.event_outlined,
          title: '手动日期',
          subtitle: manualDate.when(
            loading: () => '读取中',
            error: (error, stackTrace) => '读取失败',
            data: (value) => value == null ? '关闭' : value.toString(),
          ),
          onTap: () => _showManualDateSheet(context, ref),
        ),
      ],
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
                              '${car.brand} ${car.model}',
                              style: Theme.of(context).textTheme.titleMedium,
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
                IconButton(
                  tooltip: '设为当前车辆',
                  onPressed: car.id == null ? null : () => onApply(car.id!),
                  icon: const Icon(Icons.check_circle_outline),
                ),
                IconButton(
                  tooltip: '编辑车辆',
                  onPressed: () => onEdit(car),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '删除车辆',
                  onPressed: () => onDelete(car),
                  icon: const Icon(Icons.delete_outline),
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
          const SizedBox(height: 8),
          Text(
            '新增车辆后，会按品牌和车型加载默认保养项目，并把它设为当前应用车辆。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          LunioPrimaryButton(label: '新增车辆', onPressed: onAdd),
        ],
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
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
    return Semantics(
      button: true,
      label: '$title\n$subtitle',
      excludeSemantics: true,
      child: LunioCard(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(tokens.radiusMedium),
                  ),
                  child: Icon(icon, color: tokens.primary),
                ),
                const SizedBox(width: 12),
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
                Icon(Icons.chevron_right, color: tokens.subtle),
              ],
            ),
          ),
        ),
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
      children: [LunioCard(child: Text('加载失败：$error'))],
    );
  }
}

class _AddCarForm extends StatefulWidget {
  const _AddCarForm({this.initialCar, required this.onSubmit});

  final Car? initialCar;
  final Future<void> Function(Car car) onSubmit;

  @override
  State<_AddCarForm> createState() => _AddCarFormState();
}

class _AddCarFormState extends State<_AddCarForm> {
  static const modelOptions = [('本田', '22款思域'), ('日产', '22款轩逸')];

  int selectedIndex = 0;
  late final TextEditingController mileageController;
  late final TextEditingController roadDateController;
  String? errorText;
  bool saving = false;

  bool get isEditing => widget.initialCar != null;

  @override
  void initState() {
    super.initState();
    final initialCar = widget.initialCar;
    selectedIndex = initialCar == null
        ? 0
        : modelOptions.indexWhere(
            (model) =>
                model.$1 == initialCar.brand && model.$2 == initialCar.model,
          );
    if (selectedIndex < 0) {
      selectedIndex = 0;
    }
    mileageController = TextEditingController(
      text: initialCar?.currentMileageKm.toString() ?? '10000',
    );
    roadDateController = TextEditingController(
      text: initialCar?.roadDate.toString() ?? '2024-01-01',
    );
  }

  @override
  void dispose() {
    mileageController.dispose();
    roadDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isEditing ? '编辑车辆' : '新增车辆', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: selectedIndex,
          decoration: const InputDecoration(labelText: '品牌车型'),
          items: [
            for (var index = 0; index < modelOptions.length; index++)
              DropdownMenuItem(
                value: index,
                child: Text(
                  '${modelOptions[index].$1} ${modelOptions[index].$2}',
                ),
              ),
          ],
          onChanged: saving || isEditing
              ? null
              : (value) => setState(() => selectedIndex = value ?? 0),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: mileageController,
          enabled: !saving,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '当前里程 km'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: roadDateController,
          enabled: !saving,
          decoration: const InputDecoration(labelText: '上路日期 yyyy-MM-dd'),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            errorText!,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
          ),
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
                label: saving ? '保存中' : '保存车辆',
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
    if (mileage == null || mileage < 0) {
      setState(() => errorText = '当前里程必须是非负整数');
      return;
    }
    final roadDate = LocalDate.tryParse(roadDateController.text);
    if (roadDate == null) {
      setState(() => errorText = '上路日期必须是 yyyy-MM-dd');
      return;
    }
    final model = modelOptions[selectedIndex];
    final initialCar = widget.initialCar;
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(
        Car(
          id: initialCar?.id,
          brand: initialCar?.brand ?? model.$1,
          model: initialCar?.model ?? model.$2,
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
        errorText = '保存失败：$error';
      });
    }
  }
}

void _showAddCarSheet(BuildContext context, WidgetRef ref) {
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
        child: _AddCarForm(
          onSubmit: (car) async {
            final repository = ref.read(lunioRepositoryProvider);
            await repository.ensureDefaultMaintenanceItems();
            await repository.createCarWithDefaultItems(car);
            invalidateVehicleProviders(ref);
            if (context.mounted) {
              Navigator.of(context).pop();
              _showToast(context, '车辆已保存');
            }
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
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: _AddCarForm(
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
  );
}

void _showVehicleSwitcher(BuildContext context, WidgetRef ref) {
  final cars = ref
      .read(carsProvider)
      .maybeWhen(data: (value) => value, orElse: () => const <Car>[]);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('切换车辆', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (cars.isEmpty)
              Text('暂无车辆', style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final car in cars)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${car.brand} ${car.model}'),
                  subtitle: Text('${_formatNumber(car.currentMileageKm)} km'),
                  onTap: car.id == null
                      ? null
                      : () async {
                          await _applyCar(context, ref, car.id!);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                ),
          ],
        ),
      );
    },
  );
}

class _MaintenanceRecordForm extends StatefulWidget {
  const _MaintenanceRecordForm({
    required this.car,
    required this.items,
    this.record,
    required this.onSubmit,
  });

  final Car car;
  final List<MaintenanceItem> items;
  final MaintenanceRecord? record;
  final Future<void> Function(MaintenanceRecord record) onSubmit;

  @override
  State<_MaintenanceRecordForm> createState() => _MaintenanceRecordFormState();
}

class _MaintenanceRecordFormState extends State<_MaintenanceRecordForm> {
  late final TextEditingController dateController;
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
    dateController = TextEditingController(
      text:
          record?.date.toString() ??
          LocalDate.fromDateTime(DateTime.now()).toString(),
    );
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
    dateController.dispose();
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
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditing ? '编辑保养记录' : '新增保养记录',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: dateController,
            enabled: !saving,
            decoration: const InputDecoration(labelText: '保养日期 yyyy-MM-dd'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: mileageController,
            enabled: !saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '保养里程 km'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: costController,
            enabled: !saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '费用 元'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            enabled: !saving,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          const SizedBox(height: 14),
          Text('保养项目', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final item in availableItems)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              subtitle: item.enabled ? null : const Text('已禁用，历史记录仍可保留'),
              value: item.id != null && selectedItemIds.contains(item.id),
              onChanged: saving || item.id == null
                  ? null
                  : (value) {
                      setState(() {
                        if (value == true) {
                          selectedItemIds.add(item.id!);
                        } else {
                          selectedItemIds.remove(item.id);
                        }
                      });
                    },
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
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LunioPrimaryButton(
                  label: saving ? '保存中' : '保存记录',
                  onPressed: saving ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final date = LocalDate.tryParse(dateController.text);
    final mileage = int.tryParse(mileageController.text);
    final cost = double.tryParse(costController.text);
    if (date == null) {
      setState(() => errorText = '保养日期必须是 yyyy-MM-dd');
      return;
    }
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
          date: date,
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
        errorText = '保存失败：$error';
      });
    }
  }
}

Future<void> _showMaintenanceRecordFormSheet(
  BuildContext context,
  WidgetRef ref, {
  MaintenanceRecord? record,
}) async {
  final car = await ref.read(appliedCarProvider.future);
  final items = await ref.read(appliedCarMaintenanceItemsProvider.future);
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
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: _MaintenanceRecordForm(
          car: car!,
          items: items,
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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('删除保养记录'),
        content: Text('确定删除 ${record.date} 的保养记录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      );
    },
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
    showDragHandle: true,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.86,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Consumer(
            builder: (context, ref, child) {
              final car = ref
                  .watch(appliedCarProvider)
                  .maybeWhen(data: (value) => value, orElse: () => null);
              final items = ref.watch(appliedCarMaintenanceItemsProvider);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '保养项目配置',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      SizedBox(
                        width: 96,
                        child: LunioPrimaryButton(
                          label: '新增项目',
                          onPressed: car == null
                              ? null
                              : () => _showMaintenanceItemFormSheet(
                                  context,
                                  ref,
                                  carId: car.id!,
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    car == null
                        ? '请先新增车辆'
                        : '${car.brand} ${car.model} · 禁用项目不会出现在新增记录选择里',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: items.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stackTrace) => Text('加载失败：$error'),
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
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return LunioCard(
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
                    label: item.enabled ? '启用' : '禁用',
                    tone: item.enabled
                        ? LunioStatusTone.normal
                        : LunioStatusTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _itemRuleText(item),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                item.isDefault ? '默认项目' : '自定义项目',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () => onEdit(item),
                    child: const Text('编辑'),
                  ),
                  TextButton(
                    onPressed: () => onToggle(item),
                    child: Text(item.enabled ? '禁用' : '启用'),
                  ),
                  if (!item.isDefault)
                    TextButton(
                      onPressed: () => onDelete(item),
                      child: const Text('删除'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
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
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditing ? '编辑保养项目' : '新增保养项目',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: nameController,
            enabled: !saving && !(widget.item?.isDefault ?? false),
            decoration: const InputDecoration(labelText: '项目名称'),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('按里程提醒'),
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
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('按时间提醒'),
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
          const SizedBox(height: 12),
          TextField(
            controller: normalLimitController,
            enabled: !saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '未超期值上限'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: overdueLimitController,
            enabled: !saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '超期值上限'),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用项目'),
            value: enabled,
            onChanged: saving
                ? null
                : (value) => setState(() => enabled = value),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              errorText!,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
            ),
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
                  label: saving ? '保存中' : '保存项目',
                  onPressed: saving ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
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
        errorText = '保存失败：$error';
      });
    }
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
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
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
      _showToast(context, '操作失败：$error');
    }
  }
}

Future<void> _deleteMaintenanceItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceItem item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('删除保养项目'),
        content: Text('确定删除 ${item.name}？有历史记录的项目不能删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      );
    },
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
      _showToast(context, '删除失败：$error');
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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('清空数据'),
        content: const Text('确定清空本地车辆、保养项目、保养记录和偏好？该操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      );
    },
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
  const _ManualDateForm({required this.initialDate, required this.onSubmit});

  final LocalDate? initialDate;
  final Future<void> Function(LocalDate? date) onSubmit;

  @override
  State<_ManualDateForm> createState() => _ManualDateFormState();
}

class _ManualDateFormState extends State<_ManualDateForm> {
  late final TextEditingController dateController;
  late bool enabled;
  bool saving = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    enabled = widget.initialDate != null;
    dateController = TextEditingController(
      text:
          widget.initialDate?.toString() ??
          LocalDate.fromDateTime(DateTime.now()).toString(),
    );
  }

  @override
  void dispose() {
    dateController.dispose();
    super.dispose();
  }

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
          TextField(
            controller: dateController,
            enabled: !saving,
            decoration: const InputDecoration(labelText: '日期 yyyy-MM-dd'),
          ),
        ],
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
    final date = enabled ? LocalDate.tryParse(dateController.text) : null;
    if (enabled && date == null) {
      setState(() => errorText = '日期必须是 yyyy-MM-dd');
      return;
    }
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
        errorText = '保存失败：$error';
      });
    }
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

  String get percentText => '${progress.percent.round()}%';

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
    '绿色 < ${item.notOverdueUpperLimit.toStringAsFixed(0)}%',
    '黄色 < ${item.overdueUpperLimit.toStringAsFixed(0)}%',
  ].join(' · ');
}

String _recordItemNames(MaintenanceRecord record, List<MaintenanceItem> items) {
  return record.itemIds
      .map((id) => _itemById(items, id)?.name ?? '未知项目')
      .join('、');
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

Future<void> _deleteCar(BuildContext context, WidgetRef ref, Car car) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('删除车辆'),
        content: Text('确定删除 ${car.brand} ${car.model}？相关项目和记录会同步删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      );
    },
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

void _showToast(BuildContext context, String message) {
  final tokens = Theme.of(context).extension<LunioTokens>()!;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: tokens.ink,
      behavior: SnackBarBehavior.floating,
    ),
  );
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

// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/notifications/lunio_notification_service.dart';
import '../../../core/platform/native_files.dart';
import '../../../core/platform/native_notification_settings.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../data/backup/backup_codec.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/notification_settings.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_default_maintenance_item.dart';
import '../../../domain/entities/vehicle_model.dart';
import '../shared/shell_shared.dart';

class ProfilePreviewPage extends ConsumerStatefulWidget {
  const ProfilePreviewPage();

  @override
  ConsumerState<ProfilePreviewPage> createState() => ProfilePreviewPageState();
}

class ProfilePreviewPageState extends ConsumerState<ProfilePreviewPage> {
  int versionTapCount = 0;

  @override
  Widget build(BuildContext context) {
    final cars = ref.watch(carsProvider);
    final developerMode = ref.watch(developerModeProvider);
    final manualDate = ref.watch(manualDatePreferenceProvider);
    final notificationSettings = ref.watch(notificationSettingsProvider);
    final themeMode = ref.watch(themeModePreferenceProvider);
    final today = ref
        .watch(effectiveTodayProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => LocalDate.fromDateTime(DateTime.now()),
        );
    final appliedCar = ref
        .watch(appliedCarProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final hasCars = cars.maybeWhen(
      data: (value) => value.isNotEmpty,
      orElse: () => false,
    );
    return LunioPage(
      title: '个人中心',
      bottomPadding: 72,
      children: [
        LunioSection(
          title: '我的车辆',
          trailing: hasCars
              ? TextButton(
                  onPressed: () => showAddCarSheet(context, ref),
                  child: const Text('添加'),
                )
              : null,
          children: [
            cars.when(
              loading: () => const LunioCard(child: Text('车辆加载中...')),
              error: (error, stackTrace) =>
                  LunioCard(child: Text('车辆加载失败：${friendlyError(error)}')),
              data: (items) => VehicleList(
                cars: items,
                appliedCarId: appliedCar?.id,
                today: today,
                onAdd: () => showAddCarSheet(context, ref),
                onEdit: (car) => _showEditCarSheet(context, ref, car),
                onManageItems: (car) =>
                    showMaintenanceItemsSheet(context, ref, car: car),
                onApply: (carId) => applyCar(context, ref, carId),
                onDelete: (car) => deleteCar(context, ref, car),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LunioSection(
          title: '数据与工具',
          children: [
            ProfileSettingRow(
              title: '通知提醒',
              subtitle: notificationSettings.when(
                loading: () => '读取中',
                error: (error, stackTrace) => '读取失败',
                data: _notificationSettingsSubtitle,
              ),
              trailingLabel: '设置',
              onTap: () => showNotificationSettingsSheet(context, ref),
            ),
            ProfileSettingRow(
              title: '备份',
              subtitle: '导出全部车辆、项目配置和保养记录',
              trailingLabel: '导出',
              onTap: () => exportBackup(context, ref),
            ),
            ProfileSettingRow(
              title: '恢复',
              subtitle: '选择备份文件并恢复本地数据',
              trailingLabel: '恢复',
              onTap: () => restoreBackupFromFile(context, ref),
            ),
            ProfileSettingRow(
              title: '清空数据',
              subtitle: '删除本地车辆、项目和记录',
              trailingLabel: '清空',
              onTap: () => clearAllData(context, ref),
            ),
            if (developerMode.maybeWhen(
              data: (value) => value,
              orElse: () => false,
            ))
              ProfileSettingRow(
                title: '手动日期',
                subtitle: manualDate.when(
                  loading: () => '读取中',
                  error: (error, stackTrace) => '读取失败',
                  data: (value) =>
                      value == null ? '关闭 · 使用系统日期' : '开启 · $value',
                ),
                trailingLabel: '设置',
                onTap: () => showManualDateSheet(context, ref),
              ),
            ThemeModeSettingRow(
              mode: themeMode.maybeWhen(
                data: (value) => value,
                orElse: () => ThemeMode.system,
              ),
              onChanged: (mode) => setThemeModePreference(context, ref, mode),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _VersionFooter(
          developerModeEnabled: developerMode.maybeWhen(
            data: (value) => value,
            orElse: () => false,
          ),
          onTap: () => _handleVersionTap(context),
        ),
      ],
    );
  }

  Future<void> _handleVersionTap(BuildContext context) async {
    versionTapCount += 1;
    if (versionTapCount < 5) {
      return;
    }
    versionTapCount = 0;
    final repository = ref.read(lunioRepositoryProvider);
    final enabled = ref
        .read(developerModeProvider)
        .maybeWhen(data: (value) => value, orElse: () => false);
    if (enabled) {
      await repository.setPreferenceValue('developerModeEnabled', 'false');
      await repository.setPreferenceValue('manualDateEnabled', 'false');
      await repository.setPreferenceValue('manualDate', null);
      invalidatePreferenceProviders(ref);
      if (context.mounted) {
        showStatusOverlay(context, '开发者模式已关闭', StatusOverlayTone.info);
      }
      return;
    }
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    invalidatePreferenceProviders(ref);
    if (context.mounted) {
      showStatusOverlay(context, '开发者模式已开启', StatusOverlayTone.info);
    }
  }
}

String _notificationSettingsSubtitle(LunioNotificationSettings settings) {
  return '手机系统通知、应用内通知';
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter({
    required this.developerModeEnabled,
    required this.onTap,
  });

  final bool developerModeEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            developerModeEnabled ? '版本 1.0.0 · 开发者模式' : '版本 1.0.0',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileSettingRow extends StatelessWidget {
  const ProfileSettingRow({
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
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 5),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                backgroundColor: tokens.surface2,
                foregroundColor: tokens.primary,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                  side: BorderSide(color: tokens.line),
                ),
              ),
              child: Text(trailingLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeModeSettingRow extends StatelessWidget {
  const ThemeModeSettingRow({required this.mode, required this.onChanged});

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
              final nextMode = switch (index) {
                1 => ThemeMode.light,
                2 => ThemeMode.dark,
                _ => ThemeMode.system,
              };
              if (nextMode == mode) {
                return;
              }
              onChanged(nextMode);
            },
          ),
        ],
      ),
    );
  }
}

class VehicleList extends StatelessWidget {
  const VehicleList({
    required this.cars,
    required this.appliedCarId,
    required this.today,
    required this.onAdd,
    required this.onEdit,
    required this.onManageItems,
    required this.onApply,
    required this.onDelete,
  });

  final List<Car> cars;
  final int? appliedCarId;
  final LocalDate today;
  final VoidCallback onAdd;
  final ValueChanged<Car> onEdit;
  final ValueChanged<Car> onManageItems;
  final ValueChanged<int> onApply;
  final ValueChanged<Car> onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    if (cars.isEmpty) {
      return EmptyVehicleCard(onAdd: onAdd);
    }
    return Column(
      children: [
        for (final car in cars) ...[
          Builder(
            builder: (context) {
              final selected = car.id == appliedCarId;
              return LunioCard(
                backgroundColor: selected ? tokens.primarySoft : null,
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
                                  if (selected)
                                    const LunioStatusBadge(
                                      label: '当前',
                                      tone: LunioStatusTone.normal,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${formatMileageKm(car.currentMileageKm)} · ${car.roadDate} · ${formatCarAge(car.roadDate, today)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        CarVisual(selected: selected),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SmallActionButton(
                          label: selected ? '已应用' : '应用',
                          onPressed: car.id == null
                              ? null
                              : selected
                              ? null
                              : () => onApply(car.id!),
                        ),
                        const SizedBox(width: 8),
                        SmallActionButton(
                          label: '编辑',
                          onPressed: () => onEdit(car),
                        ),
                        const SizedBox(width: 8),
                        SmallActionButton(
                          label: '项目',
                          onPressed: () => onManageItems(car),
                        ),
                        const SizedBox(width: 8),
                        SmallActionButton(
                          label: '删除',
                          danger: true,
                          onPressed: () => onDelete(car),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class CarVisual extends StatelessWidget {
  const CarVisual({this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return CustomPaint(
      size: const Size(70, 38),
      painter: CarVisualPainter(
        bodyStart: tokens.primary,
        bodyEnd: tokens.primaryStrong,
        windowColor: selected ? tokens.surface : tokens.primarySoft,
        wheelColor: tokens.ink,
      ),
    );
  }
}

class CarVisualPainter extends CustomPainter {
  const CarVisualPainter({
    required this.bodyStart,
    required this.bodyEnd,
    required this.windowColor,
    required this.wheelColor,
  });

  final Color bodyStart;
  final Color bodyEnd;
  final Color windowColor;
  final Color wheelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: [bodyStart, bodyEnd],
      ).createShader(Offset.zero & size);
    final windowPaint = Paint()..color = windowColor;
    final wheelPaint = Paint()..color = wheelColor;
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
  bool shouldRepaint(CarVisualPainter oldDelegate) {
    return bodyStart != oldDelegate.bodyStart ||
        bodyEnd != oldDelegate.bodyEnd ||
        windowColor != oldDelegate.windowColor ||
        wheelColor != oldDelegate.wheelColor;
  }
}

class EmptyVehicleCard extends StatelessWidget {
  const EmptyVehicleCard({required this.onAdd});

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

class LoadingPage extends StatelessWidget {
  const LoadingPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return LunioPage(
      title: title,
      children: const [Center(child: CircularProgressIndicator())],
    );
  }
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({required this.title, required this.error});

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return LunioPage(
      title: title,
      children: [LunioCard(child: Text('加载失败：${friendlyError(error)}'))],
    );
  }
}

class AddCarForm extends StatefulWidget {
  const AddCarForm({
    required this.vehicleModels,
    required this.today,
    this.initialCar,
    required this.onSubmit,
    this.submitLabel,
  });

  final List<VehicleModel> vehicleModels;
  final LocalDate today;
  final Car? initialCar;
  final Future<void> Function(Car car) onSubmit;
  final String? submitLabel;

  @override
  State<AddCarForm> createState() => AddCarFormState();
}

class AddCarFormState extends State<AddCarForm> {
  late String selectedBrand;
  late String selectedModel;
  late final TextEditingController mileageController;
  late LocalDate roadDate;
  String? errorText;
  bool saving = false;

  bool get isEditing => widget.initialCar?.id != null;

  @override
  void initState() {
    super.initState();
    final initialCar = widget.initialCar;
    final options = widget.vehicleModels;
    selectedBrand = initialCar?.brand ?? options.first.brand;
    selectedModel = initialCar?.model ?? _modelsForBrand(selectedBrand).first;
    mileageController = TextEditingController(
      text: initialCar?.currentMileageKm.toString() ?? '0',
    );
    roadDate = initialCar?.roadDate ?? widget.today;
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
          VehicleModelPicker(
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
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onTap: () {
            if (!isEditing) {
              _clearZero(mileageController);
            }
          },
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          decoration: numberInputDecoration(labelText: '当前里程'),
        ),
        const SizedBox(height: 10),
        LunioPickerTile(
          label: '上路日期',
          value: formatDateForUser(roadDate),
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
                label: saving
                    ? '保存中'
                    : widget.submitLabel ?? (isEditing ? '保存车辆' : '保存车辆'),
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

  void _clearZero(TextEditingController controller) {
    if (controller.text == '0') {
      controller.clear();
    }
  }

  Future<void> _pickRoadDate() async {
    final picked = await showSimpleDatePicker(
      context,
      initialDate: roadDate,
      firstDate: const LocalDate(1990, 1, 1),
      lastDate: LocalDate.fromDateTime(
        widget.today.toDateTime().add(const Duration(days: 365)),
      ),
      today: widget.today,
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
          brand: isEditing ? initialCar!.brand : selectedBrand,
          model: isEditing ? initialCar!.model : selectedModel,
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
      if (mounted) {
        setState(() => saving = false);
      }
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

class AddCarWizard extends StatefulWidget {
  const AddCarWizard({
    required this.vehicleModels,
    required this.today,
    required this.loadDefaultItems,
    required this.onMaintenanceStepChanged,
    required this.onSubmit,
  });

  final List<VehicleModel> vehicleModels;
  final LocalDate today;
  final Future<List<VehicleDefaultMaintenanceItem>> Function(Car car)
  loadDefaultItems;
  final ValueChanged<bool> onMaintenanceStepChanged;
  final Future<void> Function(Car car, List<MaintenanceItem> items) onSubmit;

  @override
  State<AddCarWizard> createState() => AddCarWizardState();
}

class AddCarWizardState extends State<AddCarWizard> {
  Car? carDraft;
  List<MaintenanceItem>? itemDrafts;
  List<VehicleDefaultMaintenanceItem>? defaultItemTemplates;
  String? itemModelKey;
  int loadRequestId = 0;
  bool editingCarDraft = false;
  bool loadingItems = false;
  bool saving = false;
  String? errorText;

  @override
  Widget build(BuildContext context) {
    final car = carDraft;
    final items = itemDrafts;
    if (car == null || editingCarDraft) {
      return AddCarForm(
        vehicleModels: widget.vehicleModels,
        today: widget.today,
        initialCar: carDraft,
        submitLabel: '下一步',
        onSubmit: _handleCarDraft,
      );
    }
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return AddCarMaintenanceItemsStep(
      car: car,
      items: items,
      saving: saving || loadingItems,
      errorText: errorText,
      onBack: saving ? null : _returnToCarStep,
      onChanged: (nextItems) => setState(() => itemDrafts = nextItems),
      onAdd: saving ? null : _addItem,
      onRestoreDefaults: saving ? null : () => _restoreDefaultItems(car, items),
      onSubmit: saving ? null : _submit,
    );
  }

  Future<void> _handleCarDraft(Car car) async {
    final nextKey = '${car.brand}\u0000${car.model}';
    final shouldLoadItems = itemModelKey != nextKey || itemDrafts == null;
    final requestId = loadRequestId + 1;
    loadRequestId = requestId;
    widget.onMaintenanceStepChanged(true);
    setState(() {
      carDraft = car;
      editingCarDraft = false;
      loadingItems = shouldLoadItems;
      errorText = null;
      if (shouldLoadItems) {
        itemDrafts = null;
        defaultItemTemplates = null;
      }
    });
    if (!shouldLoadItems) {
      return;
    }
    try {
      final defaultItems = await widget.loadDefaultItems(car);
      if (!mounted || loadRequestId != requestId) {
        return;
      }
      final currentCar = carDraft;
      if (currentCar == null ||
          '${currentCar.brand}\u0000${currentCar.model}' != nextKey) {
        return;
      }
      setState(() {
        itemModelKey = nextKey;
        defaultItemTemplates = defaultItems;
        itemDrafts = defaultItems
            .map((item) => maintenanceItemFromDefault(item, car.sync))
            .toList();
        loadingItems = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        carDraft = null;
        editingCarDraft = false;
        loadingItems = false;
        errorText = friendlyError(error);
      });
      widget.onMaintenanceStepChanged(false);
    }
  }

  void _returnToCarStep() {
    widget.onMaintenanceStepChanged(false);
    setState(() => editingCarDraft = true);
  }

  Future<void> _submit() async {
    final car = carDraft;
    final items = itemDrafts;
    if (car == null || items == null) {
      return;
    }
    if (!items.any((item) => item.enabled)) {
      setState(() => errorText = '至少保留一个可用保养项目');
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(car, items);
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

  void _addItem() {
    final sync = SyncMetadata(
      status: SyncStatus.pendingCreate,
      updatedAt: DateTime.now(),
    );
    final item = MaintenanceItem(
      carsId: 0,
      name: '',
      enabled: true,
      remindByMileage: true,
      remindByTime: true,
      sortOrder: (itemDrafts?.length ?? 0) + 999,
      sync: sync,
    );
    showDraftMaintenanceItemFormSheet(
      context,
      item: item,
      onSubmit: (nextItem) {
        setState(() {
          itemDrafts = [...?itemDrafts, nextItem];
        });
      },
    );
  }

  Future<void> _restoreDefaultItems(
    Car car,
    List<MaintenanceItem> items,
  ) async {
    final templates = defaultItemTemplates;
    if (templates == null || templates.isEmpty) {
      return;
    }
    final selected = await _showRestoreDefaultItemsSheet(
      context,
      defaultItems: templates,
      itemDrafts: items,
    );
    if (!mounted || selected == null || selected.isEmpty) {
      return;
    }
    setState(() {
      itemDrafts = [
        ...items,
        for (final item in selected) maintenanceItemFromDefault(item, car.sync),
      ];
    });
  }
}

class AddCarMaintenanceItemsStep extends StatelessWidget {
  const AddCarMaintenanceItemsStep({
    required this.car,
    required this.items,
    required this.saving,
    required this.errorText,
    required this.onBack,
    required this.onChanged,
    required this.onAdd,
    required this.onRestoreDefaults,
    required this.onSubmit,
  });

  final Car car;
  final List<MaintenanceItem> items;
  final bool saving;
  final String? errorText;
  final VoidCallback? onBack;
  final ValueChanged<List<MaintenanceItem>> onChanged;
  final VoidCallback? onAdd;
  final VoidCallback? onRestoreDefaults;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.42;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: ItemPills(labels: ['${car.brand} ${car.model}'])),
            const SizedBox(width: 12),
            SmallActionButton(label: '新增', onPressed: onAdd, primary: true),
            const SizedBox(width: 8),
            SmallActionButton(label: '恢复', onPressed: onRestoreDefaults),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: SingleChildScrollView(
            child: MaintenanceItemList(
              items: items,
              onEdit: saving ? (_) {} : (item) => _editItem(context, item),
              onToggle: saving ? (_) {} : _toggleItem,
              onDelete: saving ? (_) {} : _deleteItem,
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(label: '上一步', onPressed: onBack),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存车辆',
                onPressed: onSubmit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _editItem(BuildContext context, MaintenanceItem item) {
    showDraftMaintenanceItemFormSheet(
      context,
      item: item,
      onSubmit: (nextItem) {
        onChanged([
          for (final current in items)
            if (identical(current, item)) nextItem else current,
        ]);
      },
    );
  }

  void _toggleItem(MaintenanceItem item) {
    final nextEnabled = !item.enabled;
    if (!nextEnabled &&
        items
            .where((current) => current.enabled && !identical(current, item))
            .isEmpty) {
      return;
    }
    onChanged([
      for (final current in items)
        if (identical(current, item))
          current.copyWith(enabled: nextEnabled)
        else
          current,
    ]);
  }

  void _deleteItem(MaintenanceItem item) {
    final nextItems = items
        .where((current) => !identical(current, item))
        .toList();
    if (!nextItems.any((current) => current.enabled)) {
      return;
    }
    onChanged(nextItems);
  }
}

Future<List<VehicleDefaultMaintenanceItem>?> _showRestoreDefaultItemsSheet(
  BuildContext context, {
  required List<VehicleDefaultMaintenanceItem> defaultItems,
  required List<MaintenanceItem> itemDrafts,
}) {
  return showLunioModalSheet<List<VehicleDefaultMaintenanceItem>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return PrototypeSheetFrame(
        title: '恢复默认项目',
        subtitle: '选择要补回的默认保养项目，保存车辆前只会更新当前页面配置',
        child: RestoreDefaultItemsSheet(
          defaultItems: defaultItems,
          itemDrafts: itemDrafts,
        ),
      );
    },
  );
}

class RestoreDefaultItemsSheet extends StatefulWidget {
  const RestoreDefaultItemsSheet({
    required this.defaultItems,
    required this.itemDrafts,
  });

  final List<VehicleDefaultMaintenanceItem> defaultItems;
  final List<MaintenanceItem> itemDrafts;

  @override
  State<RestoreDefaultItemsSheet> createState() =>
      RestoreDefaultItemsSheetState();
}

class RestoreDefaultItemsSheetState extends State<RestoreDefaultItemsSheet> {
  late final Set<String> existingNames;
  late final Set<String> selectedNames;

  @override
  void initState() {
    super.initState();
    existingNames = widget.itemDrafts
        .map((item) => normalizeItemName(item.name))
        .toSet();
    selectedNames = {
      for (final item in widget.defaultItems)
        if (!existingNames.contains(normalizeItemName(item.itemName)))
          normalizeItemName(item.itemName),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final recoverableCount = widget.defaultItems
        .where(
          (item) => !existingNames.contains(normalizeItemName(item.itemName)),
        )
        .length;
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.42;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in widget.defaultItems) ...[
                  RestoreDefaultItemRow(
                    item: item,
                    selected: selectedNames.contains(
                      normalizeItemName(item.itemName),
                    ),
                    enabled: !existingNames.contains(
                      normalizeItemName(item.itemName),
                    ),
                    onChanged: (selected) => setState(() {
                      final key = normalizeItemName(item.itemName);
                      if (selected) {
                        selectedNames.add(key);
                      } else {
                        selectedNames.remove(key);
                      }
                    }),
                  ),
                  if (item != widget.defaultItems.last)
                    const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        if (recoverableCount == 0) ...[
          const SizedBox(height: 10),
          const LunioInlineMessage(message: '当前页面已包含全部默认项目'),
        ],
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
                label: '恢复',
                onPressed: selectedNames.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop([
                          for (final item in widget.defaultItems)
                            if (selectedNames.contains(
                              normalizeItemName(item.itemName),
                            ))
                              item,
                        ]);
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '已存在的同名项目不会重复恢复',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: tokens.subtle),
        ),
      ],
    );
  }
}

class RestoreDefaultItemRow extends StatelessWidget {
  const RestoreDefaultItemRow({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final VehicleDefaultMaintenanceItem item;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? () => onChanged(!selected) : null,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: enabled ? tokens.surface2 : tokens.surface3,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Checkbox(
              value: enabled ? selected : false,
              onChanged: enabled ? (value) => onChanged(value ?? false) : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: enabled ? tokens.ink : tokens.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    defaultItemRuleText(item),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled ? tokens.muted : tokens.subtle,
                    ),
                  ),
                ],
              ),
            ),
            if (!enabled)
              Text(
                '已存在',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.subtle,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VehicleModelPicker extends StatelessWidget {
  const VehicleModelPicker({
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
  return showLunioModalSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) => PrototypeSheetFrame(
      title: '选择车型',
      subtitle: '选择车辆品牌和车型，默认保养项目会随车型创建',
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
      child: VehicleModelPickerSheet(
        vehicleModels: vehicleModels,
        selectedBrand: selectedBrand,
        selectedModel: selectedModel,
      ),
    ),
  );
}

class VehicleModelPickerSheet extends StatefulWidget {
  const VehicleModelPickerSheet({
    required this.vehicleModels,
    required this.selectedBrand,
    required this.selectedModel,
  });

  final List<VehicleModel> vehicleModels;
  final String selectedBrand;
  final String selectedModel;

  @override
  State<VehicleModelPickerSheet> createState() =>
      VehicleModelPickerSheetState();
}

class VehicleModelPickerSheetState extends State<VehicleModelPickerSheet> {
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
      mainAxisSize: MainAxisSize.min,
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
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.48,
          ),
          child: Container(
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
                            return PickerOption(
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
                            return PickerOption(
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
        ),
      ],
    );
  }
}

class PickerOption extends StatelessWidget {
  const PickerOption({
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

void showAddCarSheet(BuildContext context, WidgetRef ref) {
  showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      var isMaintenanceStep = false;
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return PrototypeSheetFrame(
            title: isMaintenanceStep ? '保养项目' : '添加车辆',
            subtitle: isMaintenanceStep ? '以下保养项目只做参考，具体以官方保养手册为准' : null,
            bottomInset: MediaQuery.of(context).viewInsets.bottom,
            child: Consumer(
              builder: (context, ref, child) {
                final vehicleModels = ref.watch(vehicleModelsProvider);
                final today = ref.watch(effectiveTodayProvider);
                if (vehicleModels.isLoading || today.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (vehicleModels.hasError) {
                  return LunioInlineMessage(message: '车型加载失败，请稍后重试');
                }
                if (today.hasError) {
                  return LunioInlineMessage(message: '日期加载失败，请稍后重试');
                }
                return vehicleModels.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) =>
                      LunioInlineMessage(message: '车型加载失败，请稍后重试'),
                  data: (models) {
                    if (models.isEmpty) {
                      return const LunioInlineMessage(message: '暂无可选车型');
                    }
                    return AddCarWizard(
                      vehicleModels: models,
                      today: today.value!,
                      loadDefaultItems: (car) async {
                        final repository = ref.read(lunioRepositoryProvider);
                        await repository.ensureBootstrapData();
                        return repository.listDefaultItemsForModel(
                          brand: car.brand,
                          model: car.model,
                        );
                      },
                      onMaintenanceStepChanged: (nextValue) {
                        if (isMaintenanceStep == nextValue) {
                          return;
                        }
                        setSheetState(() {
                          isMaintenanceStep = nextValue;
                        });
                      },
                      onSubmit: (car, items) async {
                        final repository = ref.read(lunioRepositoryProvider);
                        await repository.createCarWithMaintenanceItems(
                          car,
                          items,
                        );
                        invalidateVehicleProviders(ref);
                        if (context.mounted) {
                          Navigator.of(context).pop();
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
    },
  );
}

void _showEditCarSheet(BuildContext context, WidgetRef ref, Car car) {
  showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return PrototypeSheetFrame(
        title: '编辑车辆',
        subtitle: '品牌车型保持稳定，可更新当前里程和上路日期',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: Consumer(
          builder: (context, ref, child) {
            final vehicleModels = ref.watch(vehicleModelsProvider);
            final today = ref.watch(effectiveTodayProvider);
            if (vehicleModels.isLoading || today.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (vehicleModels.hasError) {
              return LunioInlineMessage(message: '车型加载失败，请稍后重试');
            }
            if (today.hasError) {
              return LunioInlineMessage(message: '日期加载失败，请稍后重试');
            }
            return vehicleModels.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  LunioInlineMessage(message: '车型加载失败，请稍后重试'),
              data: (models) => AddCarForm(
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
                today: today.value!,
                initialCar: car,
                onSubmit: (updatedCar) async {
                  await ref.read(lunioRepositoryProvider).updateCar(updatedCar);
                  invalidateVehicleProviders(ref);
                  if (context.mounted) {
                    Navigator.of(context).pop();
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

void showVehicleSwitcher(BuildContext context, WidgetRef ref) {
  final cars = ref
      .read(carsProvider)
      .maybeWhen(data: (value) => value, orElse: () => const <Car>[]);
  final appliedCarId = ref
      .read(appliedCarProvider)
      .maybeWhen(data: (value) => value?.id, orElse: () => null);
  if (cars.length <= 1) {
    showStatusOverlay(
      context,
      cars.isEmpty ? '请先新增车辆' : '当前只有一辆车',
      StatusOverlayTone.info,
    );
    return;
  }
  showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return PrototypeSheetFrame(
        title: '选择应用车辆',
        subtitle: '提醒、记录和新增保养记录会跟随当前车辆',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final car in cars) ...[
              SwitchCarCard(
                car: car,
                selected: car.id == appliedCarId,
                onTap: car.id == null
                    ? null
                    : () async {
                        await applyCar(context, ref, car.id!);
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

class SwitchCarCard extends StatelessWidget {
  const SwitchCarCard({
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
      color: selected ? tokens.primarySoft : tokens.surface,
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
                      '${formatNumber(car.currentMileageKm)} km · ${car.roadDate} · ${selected ? "当前应用" : "点击切换"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const CarVisual(),
            ],
          ),
        ),
      ),
    );
  }
}

void showMaintenanceItemsSheet(
  BuildContext context,
  WidgetRef ref, {
  Car? car,
}) {
  showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) => MaintenanceItemsSheetRoute(car: car),
  );
}

class MaintenanceItemsSheetRoute extends StatefulWidget {
  const MaintenanceItemsSheetRoute({required this.car});

  final Car? car;

  @override
  State<MaintenanceItemsSheetRoute> createState() =>
      MaintenanceItemsSheetRouteState();
}

class MaintenanceItemsSheetRouteState
    extends State<MaintenanceItemsSheetRoute> {
  final refreshListenable = ValueNotifier<int>(0);

  @override
  void dispose() {
    refreshListenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrototypeSheetFrame(
      title: '保养项目',
      child: MaintenanceItemsSheetContent(
        initialCar: widget.car,
        refreshListenable: refreshListenable,
      ),
    );
  }
}

class MaintenanceItemsSheetContent extends ConsumerStatefulWidget {
  const MaintenanceItemsSheetContent({
    required this.initialCar,
    required this.refreshListenable,
  });

  final Car? initialCar;
  final ValueNotifier<int> refreshListenable;

  @override
  ConsumerState<MaintenanceItemsSheetContent> createState() =>
      MaintenanceItemsSheetContentState();
}

class MaintenanceItemsSheetContentState
    extends ConsumerState<MaintenanceItemsSheetContent> {
  final scrollController = ScrollController();
  List<MaintenanceItem>? items;
  bool itemsLoading = false;
  String? itemsError;
  int? loadedCarId;
  int loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.refreshListenable.addListener(_handleExternalRefresh);
  }

  @override
  void didUpdateWidget(MaintenanceItemsSheetContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable == widget.refreshListenable) {
      return;
    }
    oldWidget.refreshListenable.removeListener(_handleExternalRefresh);
    widget.refreshListenable.addListener(_handleExternalRefresh);
  }

  @override
  void dispose() {
    widget.refreshListenable.removeListener(_handleExternalRefresh);
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetCar =
        widget.initialCar ??
        ref
            .watch(appliedCarProvider)
            .maybeWhen(data: (value) => value, orElse: () => null);
    if (targetCar?.id == null) {
      return const LunioInlineMessage(message: '请先新增车辆');
    }
    _ensureItemsLoaded(targetCar!.id!);
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.54;
    final currentItems = items;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ItemPills(
                labels: ['${targetCar.brand} ${targetCar.model}'],
              ),
            ),
            const SizedBox(width: 12),
            SmallActionButton(
              label: '新增',
              onPressed: () async {
                final saved = await showMaintenanceItemFormSheet(
                  context,
                  ref,
                  carId: targetCar.id!,
                );
                if (saved == true) {
                  widget.refreshListenable.value += 1;
                }
              },
              primary: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (itemsLoading && currentItems == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (itemsError != null && currentItems == null)
          Text('加载失败：$itemsError')
        else ...[
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: SingleChildScrollView(
              controller: scrollController,
              child: MaintenanceItemList(
                items: currentItems ?? const [],
                onEdit: (item) async {
                  final saved = await showMaintenanceItemFormSheet(
                    context,
                    ref,
                    carId: item.carsId,
                    item: item,
                  );
                  if (saved == true) {
                    await _reload(targetCar.id!);
                  }
                },
                onToggle: (item) async {
                  await toggleMaintenanceItem(context, ref, item);
                  await _reload(targetCar.id!);
                },
                onDelete: (item) async {
                  await deleteMaintenanceItem(context, ref, item);
                  await _reload(targetCar.id!);
                },
              ),
            ),
          ),
          if (itemsError != null) ...[
            const SizedBox(height: 10),
            LunioInlineMessage(
              message: '刷新失败：$itemsError',
              tone: LunioStatusTone.danger,
            ),
          ],
        ],
      ],
    );
  }

  void _ensureItemsLoaded(int carId) {
    if (loadedCarId == carId && (items != null || itemsLoading)) {
      return;
    }
    loadedCarId = carId;
    items = null;
    itemsError = null;
    itemsLoading = true;
    _loadItems(carId, resetScroll: true);
  }

  Future<void> _reload(int carId) async {
    if (!mounted) {
      return;
    }
    setState(() {
      loadedCarId = carId;
      itemsError = null;
      itemsLoading = items == null;
    });
    await _loadItems(carId);
  }

  void _handleExternalRefresh() {
    final carId = loadedCarId;
    if (carId == null) {
      return;
    }
    unawaited(_reload(carId));
  }

  Future<void> _loadItems(int carId, {bool resetScroll = false}) async {
    final generation = ++loadGeneration;
    try {
      final nextItems = await ref
          .read(lunioRepositoryProvider)
          .listMaintenanceItemsForCar(carId);
      if (!mounted || generation != loadGeneration || loadedCarId != carId) {
        return;
      }
      setState(() {
        items = nextItems;
        itemsError = null;
        itemsLoading = false;
      });
      if (resetScroll && scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
    } catch (error) {
      if (!mounted || generation != loadGeneration || loadedCarId != carId) {
        return;
      }
      setState(() {
        itemsError = friendlyError(error);
        itemsLoading = false;
      });
    }
  }
}

class MaintenanceItemList extends StatelessWidget {
  const MaintenanceItemList({
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items) ...[
          MaintenanceItemCard(
            item: item,
            onEdit: () => onEdit(item),
            onToggle: () => onToggle(item),
            onDelete: () => onDelete(item),
          ),
          if (item != items.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class MaintenanceItemCard extends StatelessWidget {
  const MaintenanceItemCard({
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
    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SmallActionButton(label: '编辑', onPressed: onEdit, secondary: true),
        const SizedBox(width: 8),
        SmallActionButton(
          label: item.enabled ? '已启用' : '已禁用',
          onPressed: onToggle,
          primary: item.enabled,
          muted: !item.enabled,
        ),
        if (onDelete != null) ...[
          const SizedBox(width: 8),
          SmallActionButton(
            label: '删除',
            tooltip: '删除',
            onPressed: onDelete,
            danger: true,
          ),
        ],
      ],
    );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(
            itemRuleText(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      ),
    );
  }
}

class MaintenanceItemForm extends StatefulWidget {
  const MaintenanceItemForm({
    required this.carId,
    this.item,
    required this.onSubmit,
  });

  final int carId;
  final MaintenanceItem? item;
  final Future<void> Function(MaintenanceItem item) onSubmit;

  @override
  State<MaintenanceItemForm> createState() => MaintenanceItemFormState();
}

class MaintenanceItemFormState extends State<MaintenanceItemForm> {
  late final TextEditingController nameController;
  late final TextEditingController mileageController;
  late final TextEditingController monthsController;
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
      text: item?.mileageIntervalKm?.toString() ?? '',
    );
    monthsController = TextEditingController(
      text: item?.timeIntervalMonths?.toString() ?? '',
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
          enabled: !saving,
          decoration: const InputDecoration(labelText: '项目名称'),
        ),
        const SizedBox(height: 10),
        ReminderRuleInputRow(
          title: '按里程提醒',
          value: remindByMileage,
          controller: mileageController,
          unit: 'km',
          onChanged: saving
              ? null
              : (value) => setState(() => remindByMileage = value),
        ),
        const SizedBox(height: 10),
        ReminderRuleInputRow(
          title: '按时间提醒',
          value: remindByTime,
          controller: monthsController,
          unit: '月',
          onChanged: saving
              ? null
              : (value) => setState(() => remindByTime = value),
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
    if (name.isEmpty) {
      setState(() => errorText = '项目名称不能为空');
      return;
    }
    if (!remindByMileage && !remindByTime) {
      setState(() => errorText = '至少选择一种提醒方式');
      return;
    }
    if (remindByMileage && (mileageInterval == null || mileageInterval <= 0)) {
      setState(() => errorText = '里程间隔必须填写正整数');
      return;
    }
    if (remindByTime && (timeInterval == null || timeInterval <= 0)) {
      setState(() => errorText = '时间间隔必须填写正整数');
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
          name: name,
          enabled: enabled,
          remindByMileage: remindByMileage,
          remindByTime: remindByTime,
          mileageIntervalKm: remindByMileage ? mileageInterval : null,
          timeIntervalMonths: remindByTime ? timeInterval : null,
          notOverdueUpperLimit: item?.notOverdueUpperLimit ?? 100,
          overdueUpperLimit: item?.overdueUpperLimit ?? 125,
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
        errorText = friendlyError(error);
      });
    }
  }
}

class ReminderRuleInputRow extends StatelessWidget {
  const ReminderRuleInputRow({
    required this.title,
    required this.value,
    required this.controller,
    required this.unit,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final TextEditingController controller;
  final String unit;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: onChanged == null ? tokens.subtle : tokens.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 116,
            child: TextField(
              controller: controller,
              enabled: value && onChanged != null,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              textAlign: TextAlign.center,
              decoration: numberInputDecoration(suffixText: unit).copyWith(
                fillColor: value
                    ? tokens.surface
                    : tokens.surface3.withValues(alpha: 0.55),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                constraints: const BoxConstraints(minHeight: 46),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

Future<bool?> showMaintenanceItemFormSheet(
  BuildContext context,
  WidgetRef ref, {
  required int carId,
  MaintenanceItem? item,
}) {
  return showLunioModalSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return PrototypeSheetFrame(
        title: item == null ? '新增保养项目' : '编辑保养项目',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: MaintenanceItemForm(
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
              Navigator.of(context).pop(true);
            }
          },
        ),
      );
    },
  );
}

Future<bool?> showDraftMaintenanceItemFormSheet(
  BuildContext context, {
  required MaintenanceItem item,
  required ValueChanged<MaintenanceItem> onSubmit,
}) {
  return showLunioModalSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return PrototypeSheetFrame(
        title: item.name.isEmpty ? '新增保养项目' : '编辑保养项目',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: MaintenanceItemForm(
          carId: 0,
          item: item,
          onSubmit: (value) async {
            onSubmit(value);
            if (context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      );
    },
  );
}

Future<void> toggleMaintenanceItem(
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
  } catch (error) {
    if (context.mounted) {
      showStatusOverlay(context, friendlyError(error), StatusOverlayTone.error);
    }
  }
}

Future<void> deleteMaintenanceItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceItem item,
) async {
  final confirmed = await showConfirmDialog(
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
  } catch (error) {
    if (context.mounted) {
      showStatusOverlay(context, friendlyError(error), StatusOverlayTone.error);
    }
  }
}

Future<void> exportBackup(BuildContext context, WidgetRef ref) async {
  try {
    final payload = await ref
        .read(lunioRepositoryProvider)
        .exportBackupPayload();
    const codec = BackupCodec();
    final json = codec.encode(payload);
    final saved = await NativeFiles.exportJsonFile(
      filename: _backupFilename(DateTime.now()),
      content: json,
    );
    if (saved && context.mounted) {
      showStatusOverlay(context, '备份完成', StatusOverlayTone.success);
    }
  } catch (error) {
    if (context.mounted) {
      showStatusOverlay(context, '备份失败：$error', StatusOverlayTone.error);
    }
  }
}

Future<void> restoreBackupFromFile(BuildContext context, WidgetRef ref) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: '恢复数据',
    message: '恢复会先清空本地车辆、保养项目、保养记录和偏好，再写入备份文件中的数据。该操作不可撤销。',
    confirmLabel: '恢复',
  );
  if (confirmed != true) {
    return;
  }
  try {
    final json = await NativeFiles.pickJsonFile();
    if (json == null) {
      return;
    }
    const codec = BackupCodec();
    final payload = codec.decode(json);
    notificationSyncGeneration++;
    await ref.read(lunioRepositoryProvider).restoreBackupPayload(payload);
    invalidateAllAppDataProviders(ref);
    if (context.mounted) {
      showStatusOverlay(context, '恢复完成', StatusOverlayTone.success);
    }
  } catch (error) {
    if (context.mounted) {
      if (isUniqueConstraintError(error)) {
        await showMessageDialog(
          context: context,
          title: '恢复失败',
          message: '恢复文件中的部分数据重复或冲突，本次恢复未写入任何数据。',
          tone: StatusOverlayTone.error,
        );
      } else {
        showStatusOverlay(context, '恢复失败：$error', StatusOverlayTone.error);
      }
    }
  }
}

String _backupFilename(DateTime dateTime) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return 'lunio-backup-'
      '${dateTime.year}'
      '${twoDigits(dateTime.month)}'
      '${twoDigits(dateTime.day)}-'
      '${twoDigits(dateTime.hour)}'
      '${twoDigits(dateTime.minute)}'
      '${twoDigits(dateTime.second)}.json';
}

Future<void> clearAllData(BuildContext context, WidgetRef ref) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: '清空数据',
    message: '确定清空本地车辆、保养项目、保养记录和偏好？该操作不可撤销。',
    confirmLabel: '清空',
  );
  if (confirmed != true) {
    return;
  }
  notificationSyncGeneration++;
  await ref.read(lunioRepositoryProvider).clearAllData();
  invalidateAllAppDataProviders(ref);
}

Future<void> showNotificationSettingsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  var initialSettings = ref
      .read(notificationSettingsProvider)
      .maybeWhen(
        data: (value) => value,
        orElse: () => const LunioNotificationSettings(),
      );
  final systemNotificationsEnabled = await refreshSystemNotificationPreference(
    ref,
  );
  if (!context.mounted) {
    return;
  }
  initialSettings = initialSettings.copyWith(
    systemNotificationsEnabled: systemNotificationsEnabled,
  );
  showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: NotificationSettingsForm(
          initialSettings: initialSettings,
          onOpenSystemSettings: () async {
            final opened =
                await NativeNotificationSettings.openNotificationSettings();
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
            if (!opened && context.mounted) {
              showStatusOverlay(
                context,
                '无法打开系统设置，请在系统设置中搜索 Lunio',
                StatusOverlayTone.info,
              );
            }
          },
          onSubmit: (settings) async {
            final systemNotificationsEnabled =
                await refreshSystemNotificationPreference(ref);
            await saveNotificationSettings(
              ref,
              settings.copyWith(
                systemNotificationsEnabled: systemNotificationsEnabled,
              ),
            );
            invalidatePreferenceProviders(ref);
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
          },
        ),
      );
    },
  );
}

Future<bool> refreshSystemNotificationPreference(WidgetRef ref) async {
  final repository = ref.read(lunioRepositoryProvider);
  final currentValue = await repository.getPreferenceValue(
    'systemNotificationsEnabled',
  );
  try {
    final enabled = await LunioNotificationService.instance
        .notificationsEnabled();
    if (currentValue != enabled.toString()) {
      await repository.setPreferenceValue(
        'systemNotificationsEnabled',
        enabled.toString(),
      );
      invalidatePreferenceProviders(ref);
    }
    return enabled;
  } catch (_) {
    return currentValue != 'false';
  }
}

Future<void> saveNotificationSettings(
  WidgetRef ref,
  LunioNotificationSettings settings,
) async {
  final repository = ref.read(lunioRepositoryProvider);
  await repository.setPreferenceValue(
    'systemNotificationsEnabled',
    settings.systemNotificationsEnabled.toString(),
  );
  await repository.setPreferenceValue(
    'inAppNotificationsEnabled',
    settings.inAppNotificationsEnabled.toString(),
  );
  await repository.setPreferenceValue(
    'maintenanceDueEnabled',
    settings.maintenanceDueEnabled.toString(),
  );
  await repository.setPreferenceValue(
    'maintenanceDueRepeat',
    settings.dueRepeatFrequency.value,
  );
}

class ReminderNotificationSegment extends StatelessWidget {
  const ReminderNotificationSegment({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class NotificationSettingsForm extends StatefulWidget {
  const NotificationSettingsForm({
    required this.initialSettings,
    required this.onOpenSystemSettings,
    required this.onSubmit,
  });

  final LunioNotificationSettings initialSettings;
  final Future<void> Function() onOpenSystemSettings;
  final Future<void> Function(LunioNotificationSettings settings) onSubmit;

  @override
  State<NotificationSettingsForm> createState() =>
      NotificationSettingsFormState();
}

class NotificationSettingsFormState extends State<NotificationSettingsForm> {
  static const dueRepeatOptions = [
    ReminderRepeatFrequency.weekly,
    ReminderRepeatFrequency.everyTwoWeeks,
    ReminderRepeatFrequency.monthly,
  ];

  late bool inAppNotificationsEnabled;
  late ReminderRepeatFrequency dueRepeatFrequency;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    inAppNotificationsEnabled = settings.inAppNotificationsEnabled;
    dueRepeatFrequency = dueRepeatOptions.contains(settings.dueRepeatFrequency)
        ? settings.dueRepeatFrequency
        : ReminderRepeatFrequency.weekly;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('通知提醒', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          SystemNotificationStatusRow(
            enabled: widget.initialSettings.systemNotificationsEnabled,
            onOpenSettings: saving ? null : widget.onOpenSystemSettings,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('应用内通知'),
            value: inAppNotificationsEnabled,
            onChanged: saving
                ? null
                : (value) => setState(() => inAppNotificationsEnabled = value),
          ),
          const SizedBox(height: 6),
          Text('到期后提醒次数', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          LunioSegmentedControl(
            values: dueRepeatOptions
                .map((frequency) => frequency.label)
                .toList(),
            selectedIndex: dueRepeatOptions.contains(dueRepeatFrequency)
                ? dueRepeatOptions.indexOf(dueRepeatFrequency)
                : 0,
            onSelected: saving
                ? (_) {}
                : (index) => setState(
                    () => dueRepeatFrequency = dueRepeatOptions[index],
                  ),
          ),
          const SizedBox(height: 18),
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
                child: FilledButton(
                  onPressed: saving ? null : _submit,
                  child: Text(saving ? '保存中...' : '保存设置'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => saving = true);
    try {
      await widget.onSubmit(
        LunioNotificationSettings(
          systemNotificationsEnabled:
              widget.initialSettings.systemNotificationsEnabled,
          inAppNotificationsEnabled: inAppNotificationsEnabled,
          maintenanceDueEnabled: true,
          dueRepeatFrequency: dueRepeatFrequency,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }
}

class SystemNotificationStatusRow extends StatelessWidget {
  const SystemNotificationStatusRow({
    required this.enabled,
    required this.onOpenSettings,
  });

  final bool enabled;
  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('手机系统通知'),
                  const SizedBox(height: 4),
                  Text(
                    enabled ? '系统已开启' : '系统已关闭',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onOpenSettings == null
                  ? null
                  : () {
                      onOpenSettings!();
                    },
              child: const Text('系统设置'),
            ),
          ],
        ),
      ),
    );
  }
}

void showManualDateSheet(BuildContext context, WidgetRef ref) {
  final initialDate = ref
      .read(manualDatePreferenceProvider)
      .maybeWhen(data: (value) => value, orElse: () => null);
  final fallbackDate = ref
      .read(effectiveTodayProvider)
      .maybeWhen(
        data: (value) => value,
        orElse: () => LocalDate.fromDateTime(DateTime.now()),
      );
  showLunioModalSheet<void>(
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
        child: ManualDateForm(
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
            }
          },
        ),
      );
    },
  );
}

class ManualDateForm extends StatefulWidget {
  const ManualDateForm({
    required this.initialDate,
    required this.fallbackDate,
    required this.onSubmit,
  });

  final LocalDate? initialDate;
  final LocalDate fallbackDate;
  final Future<void> Function(LocalDate? date) onSubmit;

  @override
  State<ManualDateForm> createState() => ManualDateFormState();
}

class ManualDateFormState extends State<ManualDateForm> {
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
            value: formatDateForUser(selectedDate),
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
        errorText = friendlyError(error);
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showSimpleDatePicker(
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

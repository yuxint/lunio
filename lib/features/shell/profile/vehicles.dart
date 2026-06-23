// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_default_maintenance_item.dart';
import '../../../domain/entities/vehicle_model.dart';
import '../shared/shell_shared.dart';
import 'maintenance_items.dart';

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
    final selected = await showRestoreDefaultItemsSheet(
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

void showEditCarSheet(BuildContext context, WidgetRef ref, Car car) {
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

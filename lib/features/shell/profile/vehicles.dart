// 车辆管理：车辆列表/卡片、添加车辆两步向导、编辑车辆、切换应用车辆。
//
// 添加车辆向导（showAddCarSheet → AddCarWizard）：
//   第一步 AddCarForm：选品牌车型（车型选择 sheet：搜索 + 品牌/车型双列，
//   列表外可自定义输入）+ 动力类型（五选一，按目录推荐值预选）
//   + 当前里程 + 上路日期 + 油箱容积（选填，加油预估用）；
//   第二步 AddCarMaintenanceItemsStep（在 maintenance_items.dart）：
//   按动力类型取默认保养项目草稿（可编辑/启停/删除/新增/恢复），点保存 →
//   Repository.createCarWithMaintenanceItems 事务落库（首辆车自动设为应用车辆）。
//
// 编辑车辆（showEditCarSheet）：品牌车型与动力类型锁定（身份字段不可改），
// 只改里程、上路日期和油箱容积。⚠ 里程可任意改小，无回退校验（R36）。
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
import '../../../domain/entities/powertrain_type.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_default_maintenance_item.dart';
import '../../../domain/entities/vehicle_model.dart';
import '../../../domain/rules/fuel_rules.dart';
import '../shared/shell_shared.dart';
import 'maintenance_items.dart';

/// 我的页车辆列表：空列表显示 EmptyVehicleCard；否则逐车渲染卡片
/// （当前应用车辆高亮 + "当前"徽章），操作按钮：应用/编辑/项目/删除。
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

/// 自绘小汽车插画（Canvas 画的车身/车窗/车轮）。
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

/// 小汽车画笔（渐变车身 + 车窗 + 两个车轮）。
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

/// 无车空卡片（"还没有车辆" + 新增按钮），提醒页和我的页共用。
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

/// 车辆基础信息表单（向导第一步 + 编辑车辆复用）：
/// 新增模式可选品牌车型、填里程/上路日期/油箱容积（选填）；
/// 编辑模式品牌车型只读回显。initialCar != null 且有 id → 编辑模式。
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

  /// 选中的动力类型。选车型时重置为该车型的目录推荐值，用户可改；
  /// 自定义车型没有推荐值，从燃油开始。
  late PowertrainType selectedPowertrain;
  late final TextEditingController mileageController;
  late final TextEditingController capacityController;
  late LocalDate roadDate;
  String? errorText;
  bool saving = false;

  bool get isEditing => widget.initialCar?.id != null;

  @override
  void initState() {
    super.initState();
    final initialCar = widget.initialCar;
    final options = widget.vehicleModels;
    // 新增时默认选中目录第一项（老目录时代写死的"本田 思域（燃油版）"
    // 已随 ADR 0003 废弃）；编辑模式回显当前车。
    selectedBrand = initialCar?.brand ?? options.first.brand;
    selectedModel = initialCar?.model ?? _modelsForBrand(selectedBrand).first;
    selectedPowertrain =
        initialCar?.powertrainType ??
        _recommendedPowertrain(selectedBrand, selectedModel);
    mileageController = TextEditingController(
      text: initialCar?.currentMileageKm.toString() ?? '0',
    );
    capacityController = TextEditingController(
      text: _capacityInputText(initialCar?.tankCapacityLiters),
    );
    roadDate = initialCar?.roadDate ?? widget.today;
  }

  @override
  void dispose() {
    mileageController.dispose();
    capacityController.dispose();
    super.dispose();
  }

  /// 容积回填文本：整数不带小数位（55），非整数按原样（64.5、55.1234）。
  static String _capacityInputText(double? liters) {
    if (liters == null) {
      return '';
    }
    return liters % 1 == 0 ? liters.toStringAsFixed(0) : liters.toString();
  }

  /// 目录推荐动力类型：按（品牌, 车型）查 vehicleModels；自定义车型
  /// 不在目录里，没有推荐值，默认燃油。
  PowertrainType _recommendedPowertrain(String brand, String model) {
    for (final candidate in widget.vehicleModels) {
      if (candidate.brand == brand && candidate.model == model) {
        return candidate.template;
      }
    }
    return PowertrainType.fuel;
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
                // 换车型时动力类型重置为该车型的推荐值（用户可再改）。
                selectedPowertrain = _recommendedPowertrain(brand, model);
              });
            },
          ),
        const SizedBox(height: 10),
        // 动力类型：新增可选（决定默认保养项目），编辑只读（身份字段）。
        if (isEditing)
          LunioPickerTile(
            label: '动力类型',
            value: widget.initialCar!.powertrainType.label,
            enabled: false,
            onTap: null,
          )
        else
          PowertrainPicker(
            selected: selectedPowertrain,
            enabled: !saving,
            onSelected: (next) => setState(() {
              selectedPowertrain = next;
            }),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: mileageController,
          enabled: !saving,
          // 数字输入统一用数字键盘（与油箱容积同款方式）。
          keyboardType: const TextInputType.numberWithOptions(),
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
        const SizedBox(height: 10),
        TextField(
          controller: capacityController,
          enabled: !saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            // 最多四位小数：整数部分至多 3 位 + 可选小数点 + 至多 4 位小数。
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,4}')),
          ],
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          // 标签始终浮在框顶：默认行为下空值未聚焦时标签会落进输入框
          // 中间（占位符位置），与上方字段（标签都在框顶）不一致。
          decoration: numberInputDecoration(
            labelText: '油箱容积（选填）',
            suffixText: '升',
          ).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        LunioFormActions(
          confirmLabel: widget.submitLabel ?? '保存车辆',
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _submit,
          saving: saving,
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

  /// 选上路日期：1990-01-01 ~ 生效今天+365。
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

  /// 提交车辆草稿：里程非负校验 → 油箱容积校验（选填，1–999、
  /// 最多四位小数，规则在 FuelRules）→ 构造 Car（编辑保留原品牌车型
  /// 与 id）→ onSubmit → 成功不关 sheet（由外层向导控制）；
  /// 失败表单内展示错误。
  Future<void> _submit() async {
    final mileage = int.tryParse(mileageController.text);
    if (mileage == null || mileage < 0) {
      setState(() => errorText = '当前里程必须是非负整数');
      return;
    }
    final capacityText = capacityController.text.trim();
    double? tankCapacity;
    if (capacityText.isNotEmpty) {
      final parsed = double.tryParse(capacityText);
      var valid = parsed != null;
      if (valid) {
        try {
          FuelRules.validateTankCapacity(parsed);
        } on ArgumentError {
          valid = false;
        }
      }
      if (!valid) {
        setState(() => errorText = '油箱容积需在 1–999 升之间，最多四位小数');
        return;
      }
      tankCapacity = parsed;
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
          powertrainType: isEditing
              ? initialCar!.powertrainType
              : selectedPowertrain,
          currentMileageKm: mileage,
          roadDate: roadDate,
          tankCapacityLiters: tankCapacity,
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

/// 添加车辆两步向导（第一步车辆信息 → 第二步保养项目草稿）。
/// onMaintenanceStepChanged 通知外层 sheet 切标题。
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
  /// 第一步的车辆草稿（非 null 且 !editingCarDraft 时进入第二步）。
  Car? carDraft;

  /// 第二步的项目草稿列表（null = 正在加载默认模板）。
  List<MaintenanceItem>? itemDrafts;

  /// 当前车型对应的默认模板（"恢复"功能用）。
  List<VehicleDefaultMaintenanceItem>? defaultItemTemplates;

  /// 已加载模板的车型标识（brand\u0000model\u0000动力类型）：返回第一步
  /// 没换车型且没换动力类型时不重新加载，保留用户已做的草稿修改。
  String? itemModelKey;

  /// 加载防串号：只接受最新一次请求的结果（写法正确）。
  int loadRequestId = 0;

  /// "上一步"标记：true 时显示第一步表单（复用 carDraft 作初始值）。
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

  /// 第一步"下一步"：记住车辆草稿；车型或动力类型变了才异步加载默认模板
  /// （loadDefaultItems：ensureBootstrapData + 车型专属模板优先、
  /// 否则 listDefaultItemsForPowertrain），模板转成项目草稿；
  /// 同车型同动力返回上一步则跳过加载。
  Future<void> _handleCarDraft(Car car) async {
    final nextKey =
        '${car.brand}\u0000${car.model}\u0000${car.powertrainType.wire}';
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
          '${currentCar.brand}\u0000${currentCar.model}\u0000'
              '${currentCar.powertrainType.wire}' != nextKey) {
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

  /// 第二步"上一步"：置 editingCarDraft=true 重新显示第一步表单。
  void _returnToCarStep() {
    widget.onMaintenanceStepChanged(false);
    setState(() => editingCarDraft = true);
  }

  /// 最终提交：至少一个启用项目 → onSubmit（外层走 Repository 事务）
  /// → 成功关 sheet；失败错误展示在第二步。
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

  /// 草稿列表"新增"：弹草稿项目表单（showDraftMaintenanceItemFormSheet，
  /// 在 maintenance_items.dart），确认后追加进草稿。
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

  /// 草稿列表"恢复"：勾选式补回被删的默认项目。
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

/// 品牌车型选择 tile（点击弹出选择 sheet，返回 (brand, model) 元组）。
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
    builder: (context) => PrototypeSheetFrame(
      title: '选择车型',
      subtitle: '选择车辆品牌和车型，列表外的车型可自定义输入',
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
      child: VehicleModelPickerSheet(
        vehicleModels: vehicleModels,
        selectedBrand: selectedBrand,
        selectedModel: selectedModel,
      ),
    ),
  );
}

/// 车型选择 sheet：搜索框（品牌+车型名包含匹配）+ 左品牌右车型双列。
/// 点车型行即确认返回。
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
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '没有匹配车型',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      // 无匹配时自定义入口也要可用（目录外老车的主要入口）。
                      PickerOption(
                        label: '＋ 自定义输入…',
                        selected: false,
                        enabled: true,
                        onTap: () async {
                          final value = await _showCustomModelDialog(context);
                          if (value != null && context.mounted) {
                            Navigator.of(context).pop(value);
                          }
                        },
                      ),
                    ],
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
                          // +1：末尾固定一行"自定义输入"入口——目录以懂车帝
                          // 为准（ADR 0003），覆盖不到的老车从这里手输。
                          itemCount: models.length + 1,
                          itemBuilder: (context, index) {
                            if (index == models.length) {
                              return PickerOption(
                                label: '＋ 自定义输入…',
                                selected: false,
                                enabled: true,
                                onTap: () async {
                                  final value = await _showCustomModelDialog(
                                    context,
                                  );
                                  if (value != null && context.mounted) {
                                    Navigator.of(context).pop(value);
                                  }
                                },
                              );
                            }
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

/// 动力类型选择行（添加向导第一步）：五个选项（燃油/混动/插混/增程/纯电）
/// 行内 chip 点选，不弹 sheet。外观与 LunioPickerTile 同构——同样的
/// InputDecorator 外框 + label，只是值区换成 chip 组。
class PowertrainPicker extends StatelessWidget {
  const PowertrainPicker({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final PowertrainType selected;
  final bool enabled;
  final ValueChanged<PowertrainType> onSelected;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: '动力类型', enabled: enabled),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in PowertrainType.values)
            _PowertrainChip(
              label: type.label,
              selected: type == selected,
              enabled: enabled,
              onTap: () => onSelected(type),
            ),
        ],
      ),
    );
  }
}

/// 动力类型 chip 单体：选中主色弱底（primarySoft）+ 主色文字，
/// 未选透明底描边；配色沿用全局 chip 惯例（见 LunioTokens 注释）。
class _PowertrainChip extends StatelessWidget {
  const _PowertrainChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? tokens.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
          border: Border.all(
            color: selected ? tokens.primary : tokens.line,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? tokens.primary : tokens.muted,
          ),
        ),
      ),
    );
  }
}

/// 双列选择器的单行选项。
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

/// 自定义车型弹窗：品牌/车型两个必填输入框，确认返回 (brand, model)。
/// 目录（懂车帝命名）覆盖不到的车型从这里手输；取消/校验失败返回 null。
Future<(String, String)?> _showCustomModelDialog(BuildContext context) {
  final brandController = TextEditingController();
  final modelController = TextEditingController();
  return showDialog<(String, String)>(
    context: context,
    builder: (dialogContext) {
      String? errorText;
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void submit() {
            final brand = brandController.text.trim();
            final model = modelController.text.trim();
            if (brand.isEmpty || model.isEmpty) {
              setDialogState(() => errorText = '品牌和车型都要填写');
              return;
            }
            Navigator.of(dialogContext).pop((brand, model));
          }

          return AlertDialog(
            title: const Text('自定义车型'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: brandController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '品牌'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: modelController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: const InputDecoration(labelText: '车型'),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Theme.of(dialogContext)
                          .extension<LunioTokens>()!
                          .danger,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              TextButton(onPressed: submit, child: const Text('确定')),
            ],
          );
        },
      );
    },
  );
}

/// 添加/编辑车辆 sheet 共用的数据前置检查（R32 提取，替代两份重复的
/// "车型/日期加载失败"检查块）：任一数据在加载中显示加载圈、任一出错
/// 给对应行内提示。返回 null 表示数据就绪，调用方继续渲染表单。
Widget? carFormLoadGuard(
  AsyncValue<List<VehicleModel>> vehicleModels,
  AsyncValue<LocalDate> today,
) {
  if (vehicleModels.isLoading || today.isLoading) {
    return const Center(child: CircularProgressIndicator());
  }
  if (vehicleModels.hasError) {
    return const LunioInlineMessage(message: '车型加载失败，请稍后重试');
  }
  if (today.hasError) {
    return const LunioInlineMessage(message: '日期加载失败，请稍后重试');
  }
  return null;
}

/// ★ 添加车辆 sheet 入口（我的页"添加"/空卡片"新增车辆"/提醒页空卡片）。
/// StatefulBuilder 持有"当前是否第二步"以切换 sheet 标题；
/// watch 车型目录与生效今天，加载失败给出行内提示；
/// 向导提交 → createCarWithMaintenanceItems（事务：车+项目+首车设应用车辆）
/// → invalidateVehicleProviders → 关 sheet。
void showAddCarSheet(BuildContext context, WidgetRef ref) {
  showLunioModalSheet<void>(
    context: context,
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
                final guard = carFormLoadGuard(vehicleModels, today);
                if (guard != null) {
                  return guard;
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
                        // 车型专属模板优先（如思域的 civicFuel，ADR 0004）；
                        // 未命中（非目录车型/无专属模板/改选了其他动力类型）
                        // 回退动力类型通用模板。
                        final vehicleSpecific =
                            await repository.listDefaultItemsForVehicleModel(
                          brand: car.brand,
                          model: car.model,
                          selectedPowertrain: car.powertrainType,
                        );
                        if (vehicleSpecific != null) {
                          return vehicleSpecific;
                        }
                        return repository.listDefaultItemsForPowertrain(
                          powertrainType: car.powertrainType,
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
                          showStatusOverlay(
                            context,
                            '车辆已保存',
                            StatusOverlayTone.success,
                          );
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

/// ★ 编辑车辆 sheet：AddCarForm 编辑模式（品牌车型只读）→
/// updateCar（写里程/日期/容积）→ invalidate → 关 sheet。
/// 车型目录为空时兜底用当前车拼一个假选项（只是为了让表单不炸）。
void showEditCarSheet(BuildContext context, WidgetRef ref, Car car) {
  showLunioModalSheet<void>(
    context: context,
    builder: (context) {
      return PrototypeSheetFrame(
        title: '编辑车辆',
        subtitle: '品牌车型保持稳定，可更新当前里程、上路日期和油箱容积',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: Consumer(
          builder: (context, ref, child) {
            final vehicleModels = ref.watch(vehicleModelsProvider);
            final today = ref.watch(effectiveTodayProvider);
            final guard = carFormLoadGuard(vehicleModels, today);
            if (guard != null) {
              return guard;
            }
            return vehicleModels.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  LunioInlineMessage(message: '车型加载失败，请稍后重试'),
              data: (models) => AddCarForm(
                vehicleModels: models.isEmpty
                    ? [
                        // 目录为空时兜底用当前车拼一个假选项（表单不炸）；
                        // 推荐动力类型用当前车自己的。
                        VehicleModel(
                          brand: car.brand,
                          model: car.model,
                          template: car.powertrainType,
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
                    showStatusOverlay(
                      context,
                      '车辆已保存',
                      StatusOverlayTone.success,
                    );
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

/// ★ 提醒页右上角"切换车辆"sheet：列出全部车，点非当前车 →
/// applyCar（写偏好 + invalidate）→ 关 sheet。
/// 切换应用车辆 sheet（提醒页右上角入口）。
/// 先 await 车辆列表与应用车辆（R23：loading 期 read 会拿到空列表，
/// 误报"请先新增车辆"）；加载失败 toast 返回；单辆车提示后返回。
/// 弹出后的选中卡片点击 → applyCar 写偏好 → 关 sheet。
Future<void> showVehicleSwitcher(BuildContext context, WidgetRef ref) async {
  final List<Car> cars;
  final int? appliedCarId;
  try {
    cars = await ref.read(carsProvider.future);
    appliedCarId = (await ref.read(appliedCarProvider.future))?.id;
  } catch (_) {
    if (context.mounted) {
      showStatusOverlay(context, '车辆加载失败', StatusOverlayTone.error);
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
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
    builder: (sheetContext) {
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
                        await applyCar(sheetContext, ref, car.id!);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
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

/// 切换 sheet 里的单辆车卡片（当前车高亮不可点）。
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

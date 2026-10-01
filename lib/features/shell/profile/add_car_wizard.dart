// 添加车辆两步向导：车辆基础信息表单（第一步）+ 两步之间的草稿状态机。
//
// 在 App 中的位置：profile 域，被 vehicles.dart 的 showAddCarSheet 装进
// sheet；第二步的保养项目草稿列表组件在 maintenance_items.dart。
// 职责分界：
//   - AddCarForm：第一步表单（品牌车型/动力类型/里程/上路日期/油箱容积），
//     编辑车辆复用（品牌车型与动力类型只读），校验与提交生命周期走
//     表单运行时把手 FormSheetHandle（ADR 0016）；字段决策（初始态、
//     换车型重置推荐动力类型、校验、提交载荷构造）收在
//     car_form_controller.dart 的 plain-Dart 控制器（单测见
//     test/features/car_form_controller_test.dart），本 State 只做渲染
//     与事件转发；
//   - AddCarWizard + AddCarWizardController：两步之间的草稿状态机收在
//     plain-Dart 控制器（同键复用/换键重转/失败回退/竞态防御，模板加载
//     经注入，单测见 test/features/add_car_wizard_controller_test.dart），
//     widget 只做渲染、sheet 交互与刷新；
//   - 默认模板经 defaultItemsTemplateProvider（providers.dart，按车型键
//     缓存，车型专属优先回退通用，ADR 0004）转成项目草稿（可编辑/启停/
//     删除/新增/恢复），点保存由外层走动作层事务（首辆车自动设为应用车辆）。
//
// ≈ Java Web 里向导页 + BackingBean：widget 是视图，控制器持有跨步状态。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
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
import '../shared/shell_shared.dart';
import 'car_form_controller.dart';
import 'maintenance_items.dart';
import 'vehicle_model_picker.dart';

/// 车辆基础信息表单（向导第一步 + 编辑车辆复用）：
/// 新增模式可选品牌车型、填里程/上路日期/油箱容积（选填）；
/// 编辑模式品牌车型只读回显。initialCar != null 且有 id → 编辑模式。
/// [closeOnSubmit]：提交成功是否关 sheet——编辑车辆 sheet 传 true
/// （关场+toast 归表单运行时，ADR 0016）；向导第一步传 false（成功 =
/// 推进第二步，经 handle.run 只走 saving/错误生命周期）。
class AddCarForm extends StatefulWidget implements FormSheetHandleWidget {
  const AddCarForm({
    required this.vehicleModels,
    required this.today,
    required this.handle,
    required this.closeOnSubmit,
    this.initialCar,
    required this.onSubmit,
    this.submitLabel,
  });

  final List<VehicleModel> vehicleModels;
  final LocalDate today;
  final Car? initialCar;

  /// 表单运行时把手（ADR 0016）：saving/行内错误/提交/关闭都经它。
  @override
  final FormSheetHandle<void> handle;

  /// 提交成功是否关 sheet（见类注释）。
  final bool closeOnSubmit;
  final Future<void> Function(Car car) onSubmit;
  final String? submitLabel;

  @override
  State<AddCarForm> createState() => AddCarFormState();
}

class AddCarFormState extends State<AddCarForm>
    with FormSheetHandleHost<AddCarForm> {
  // ---- 表单决策体（car_form_controller.dart）：字段态、初始态回填、
  // 换车型重置推荐动力类型、校验与提交载荷构造都在控制器里，本 State
  // 持有生命周期并转发事件（同 _FuelRecordFormState 接法）。

  /// 表单决策体控制器（2026-10-01 从本 State 收编，决策清单见其文件头）。
  late final CarFormController form;

  bool get isEditing => form.isEditing;

  @override
  void initState() {
    super.initState();
    form = CarFormController(
      vehicleModels: widget.vehicleModels,
      today: widget.today,
      initialCar: widget.initialCar,
      ui: CarFormUi(
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
      // 校验错误的文案经把手显示（ADR 0016 错误统一在把手上）。
      reportError: setFormError,
    );
  }

  @override
  void dispose() {
    form.dispose();
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
            selectedBrand: form.selectedBrand,
            selectedModel: form.selectedModel,
            enabled: !saving,
            onSelected: (brand, model) {
              // 换车型：决策（重置推荐动力类型）在控制器，这里只刷新。
              setState(() => form.selectModel(brand, model));
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
            selected: form.selectedPowertrain,
            enabled: !saving,
            onSelected: (next) => setState(() {
              form.setPowertrain(next);
            }),
          ),
        const SizedBox(height: 10),
        LunioNumberField(
          controller: form.mileageController,
          enabled: !saving,
          labelText: '当前里程',
          onTap: isEditing
              ? null
              : () => LunioNumberField.clearLeadingZero(form.mileageController),
        ),
        const SizedBox(height: 10),
        LunioPickerTile(
          label: '上路日期',
          value: formatDateForUser(form.roadDate),
          enabled: !saving,
          onTap: _pickRoadDate,
        ),
        const SizedBox(height: 10),
        LunioNumberField(
          controller: form.capacityController,
          enabled: !saving,
          // 最多四位小数，整数部分至多 3 位。
          decimals: 4,
          maxIntegerDigits: 3,
          labelText: '油箱容积（选填）',
          suffixText: '升',
          // 标签始终浮在框顶：默认行为下空值未聚焦时标签会落进输入框
          // 中间（占位符位置），与上方字段（标签都在框顶）不一致。
          alwaysFloatLabel: true,
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        LunioFormActions(
          confirmLabel: widget.submitLabel ?? '保存车辆',
          onCancel: () => widget.handle.close(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 选上路日期：边界（1990-01-01 ~ 生效今天+365）与落值在控制器，
  /// 这里只负责重建日期行。
  Future<void> _pickRoadDate() async {
    await form.pickRoadDate();
    if (mounted) {
      setState(() {});
    }
  }

  /// 提交车辆草稿：校验与 Car 载荷构造在控制器（失败报行内错误、
  /// 返回 null 早退）。
  Future<void> _submit() async {
    final car = form.submitPayload();
    if (car == null) {
      return;
    }
    // 提交生命周期归表单运行时（ADR 0016）：编辑 sheet 走 submit
    // （成功关场+toast），向导第一步走 run（成功推进阶段，不关场）。
    await (widget.closeOnSubmit
        ? widget.handle.submit(() => widget.onSubmit(car))
        : widget.handle.run(() => widget.onSubmit(car)));
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

/// 模板 family 的缓存键：品牌/车型/所选动力类型（record 结构化相等，
/// 与 providers.dart 的 defaultItemsTemplateProvider key 同形）。
({String brand, String model, PowertrainType powertrain}) carModelKey(
  Car car,
) => (brand: car.brand, model: car.model, powertrain: car.powertrainType);

/// 向导阶段（AddCarWizardController 的派生值，widget 据此渲染分支）。
enum AddCarWizardStage {
  /// 第一步：无车辆草稿，或正在编辑草稿（"上一步"回看）。
  form,

  /// 车辆草稿已提交、模板还没转出（统一转圈）。
  loading,

  /// 第二步：项目草稿就绪。
  items,
}

/// 默认模板加载注入点：按"品牌·车型·动力类型"键取默认项目模板。
/// 生产接线 defaultItemsTemplateProvider family；纯 Dart 控制器不碰
/// WidgetRef，测试注入 fake 控制时序（成功/抛错/挂起）。
typedef DefaultTemplateLoader
    = Future<List<VehicleDefaultMaintenanceItem>> Function(
      ({String brand, String model, PowertrainType powertrain}) key,
    );

/// 添加车辆两步向导（第一步车辆信息 → 第二步保养项目草稿）。
/// onMaintenanceStepChanged 通知外层 sheet 切标题（入口函数经
/// handle.setFrame 接线，ADR 0016）。
class AddCarWizard extends ConsumerStatefulWidget
    implements FormSheetHandleWidget {
  const AddCarWizard({
    required this.vehicleModels,
    required this.today,
    required this.handle,
    required this.onMaintenanceStepChanged,
    required this.onSubmit,
  });

  final List<VehicleModel> vehicleModels;
  final LocalDate today;

  /// 表单运行时把手（ADR 0016）：saving/行内错误/提交/关闭都经它，
  /// 与第一步表单共用同一把手（错误位/提交态全 sheet 一份）。
  @override
  final FormSheetHandle<void> handle;
  final ValueChanged<bool> onMaintenanceStepChanged;
  final Future<void> Function(Car car, List<MaintenanceItem> items) onSubmit;

  @override
  ConsumerState<AddCarWizard> createState() => AddCarWizardState();
}

class AddCarWizardState extends ConsumerState<AddCarWizard>
    with FormSheetHandleHost<AddCarWizard> {

  /// 草稿状态机（模板加载经 provider 注入，纯 Dart 可单测）。
  late final AddCarWizardController _controller = AddCarWizardController(
    loadTemplate: (key) => ref.read(defaultItemsTemplateProvider(key).future),
  );

  @override
  Widget build(BuildContext context) {
    switch (_controller.stage) {
      case AddCarWizardStage.form:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模板加载失败退回第一步时错误要真正可见（此前 errorText 只在
            // 第二步分支渲染，第一步实际什么都不显示）。
            if (_controller.errorText != null) ...[
              LunioInlineMessage(
                message: _controller.errorText!,
                tone: LunioStatusTone.danger,
              ),
              const SizedBox(height: 10),
            ],
            AddCarForm(
              vehicleModels: widget.vehicleModels,
              today: widget.today,
              initialCar: _controller.carDraft,
              handle: widget.handle,
              closeOnSubmit: false,
              submitLabel: '下一步',
              onSubmit: _handleCarDraft,
            ),
          ],
        );
      case AddCarWizardStage.loading:
      case AddCarWizardStage.items:
        final car = _controller.carDraft!;
        // 常驻 watch：保活模板 family（"恢复默认项目"要读它，实例无人监听
        // 会被逐出）。加载态由阶段统一表现，这里不取值。
        ref.watch(defaultItemsTemplateProvider(carModelKey(car)));
        if (_controller.stage == AddCarWizardStage.items) {
          return AddCarMaintenanceItemsStep(
            car: car,
            items: _controller.itemDrafts!,
            saving: saving,
            errorText: errorText,
            onBack: saving ? null : _returnToCarStep,
            onEdit: saving ? (_) {} : _editItem,
            onToggle: saving ? (_) {} : _toggleItem,
            onDelete: saving ? (_) {} : _deleteItem,
            onAdd: saving ? null : _addItem,
            onRestoreDefaults: saving ? null : _restoreDefaultItems,
            onSubmit: saving ? null : _submit,
          );
        }
        // 模板加载中（或已就绪但草稿还没转出），统一转圈。
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator()),
        );
    }
  }

  /// 控制器每次状态迁移后的统一收尾：同步 sheet 标题（离开第一步后
  /// 显示"保养项目"）并触发重建。控制器的调用方都要走这里。
  void _refresh() {
    widget.onMaintenanceStepChanged(
      _controller.stage != AddCarWizardStage.form,
    );
    setState(() {});
  }

  /// 第一步"下一步"：状态迁移归控制器，这里只做刷新与标题同步。
  /// 提交的同步段先落地（转圈立即出现），再等模板结果；顺带清 mixin
  /// 行内错误——第二步保存失败的旧文案不随"下一步"带进新一步（控制器
  /// 的模板错误由 submitCarDraft 自己清，两条通道互不代管）。
  Future<void> _handleCarDraft(Car car) async {
    final pending = _controller.submitCarDraft(car);
    setFormError(null);
    _refresh();
    await pending;
    if (mounted) {
      _refresh();
    }
  }

  /// 第二步"上一步"：回第一步表单（复用车辆草稿，项目草稿保留）。
  void _returnToCarStep() {
    _controller.returnToCarStep();
    _refresh();
  }

  /// 草稿列表"编辑"：弹草稿项目表单（交互与 [_addItem] 同型——sheet
  /// 留在向导 State），确认后按 identity 替换（editDraft 恒成功）。
  void _editItem(MaintenanceItem item) {
    showDraftMaintenanceItemFormSheet(
      context,
      item: item,
      onSubmit: (nextItem) {
        setState(() => _controller.editDraft(item, nextItem));
      },
    );
  }

  /// 草稿列表"启停/删除"：变更与守卫在控制器的变更面，被拒弹轻提示
  /// ——与落库路径停用最后一个启用项的 toast 口径一致（2026-09-26 起
  /// 草稿侧不再是静默拦截）。
  void _toggleItem(MaintenanceItem item) {
    final error = _controller.toggleDraft(item);
    if (error != null) {
      showStatusOverlay(context, error, StatusOverlayTone.error);
      return;
    }
    setState(() {});
  }

  /// 草稿列表"删除"：守卫同 [_toggleItem]。
  void _deleteItem(MaintenanceItem item) {
    final error = _controller.removeDraft(item);
    if (error != null) {
      showStatusOverlay(context, error, StatusOverlayTone.error);
      return;
    }
    setState(() {});
  }

  /// 最终提交：「至少一个启用项目」由草稿变更面守卫（启停/删除被拒不
  /// 生效），提交时不可能零启用项、不再复查；提交生命周期归表单运行时
  /// （成功关场+toast 归 handle，ADR 0016）。
  Future<void> _submit() async {
    final car = _controller.carDraft;
    final items = _controller.itemDrafts;
    if (car == null || items == null) {
      return;
    }
    await widget.handle.submit(() => widget.onSubmit(car, items));
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
      sortOrder: (_controller.itemDrafts?.length ?? 0) + 999,
      sync: sync,
    );
    showDraftMaintenanceItemFormSheet(
      context,
      item: item,
      onSubmit: (nextItem) {
        setState(() => _controller.addDraft(nextItem));
      },
    );
  }

  /// 草稿列表"恢复"：勾选 sheet 交互留在这里，模板数据与合并归控制器
  /// （模板读控制器缓存——build 里常驻 watch 保活 family，缓存必已就绪）。
  Future<void> _restoreDefaultItems() async {
    final car = _controller.carDraft;
    final templates = _controller.loadedTemplates;
    if (car == null || templates.isEmpty) {
      return;
    }
    final selected = await showRestoreDefaultItemsSheet(
      context,
      defaultItems: templates,
      itemDrafts: _controller.itemDrafts ?? const [],
    );
    if (!mounted || selected == null || selected.isEmpty) {
      return;
    }
    setState(() => _controller.restoreDefaults(selected));
  }
}

/// 添加车辆向导的草稿状态机（plain-Dart 控制器，仿记录表单的
/// RecordCostFormController）：持有第一步车辆草稿与第二步项目草稿的
/// 全部迁移规则——同车型键复用草稿、换键重转、模板加载的竞态防御、
/// 失败回退第一步。第二步项目草稿的变更面（编辑/启停/删除，与新增/
/// 恢复默认一起）也收在这里：启停/删除内置「至少一个启用项目」守卫，
/// 被拒返回提示文案（widget 负责展示），提交时零启用项因此不可达、
/// 无需提交校验。模板加载经 [loadTemplate] 注入（生产接
/// defaultItemsTemplateProvider family，测试注入 fake），本类不碰
/// WidgetRef/BuildContext；重建（setState）、sheet/pop 与最终提交的
/// saving 生命周期留在 widget，调用方在每次调用后自行刷新。
/// ≈ Java Web 里向导页抽出来的 BackingBean。
class AddCarWizardController {
  AddCarWizardController({required this.loadTemplate});

  /// 默认模板加载注入点（键与 family 缓存键同形，见 [DefaultTemplateLoader]）。
  final DefaultTemplateLoader loadTemplate;

  /// 第一步的车辆草稿（非 null 且 [editingCarDraft] 为 false 时进第二步）。
  Car? carDraft;

  /// 第二步的项目草稿列表（null = 还没从模板转出）。
  List<MaintenanceItem>? itemDrafts;

  /// 当前草稿所属的车型键（品牌·车型·动力类型）："上一步"回到第一步
  /// 再进来时同键直接复用草稿（保留用户已做的修改），换键才重新转。
  ({String brand, String model, PowertrainType powertrain})? itemModelKey;

  /// "上一步"标记：true 时显示第一步表单（复用 [carDraft] 作初始值）。
  bool editingCarDraft = false;

  /// 模板加载失败的行内错误（第一步顶部可见）。下一次提交车辆草稿时清空。
  String? errorText;

  /// 最近一次成功加载的默认模板（"恢复默认项目"的数据源）。模板是内置
  /// 只读数据（family 常驻缓存，见 providers.dart），持有一份副本后
  /// widget 不必回读 provider。
  List<VehicleDefaultMaintenanceItem> _loadedTemplates = const [];

  /// 最近一次成功加载的默认模板。
  List<VehicleDefaultMaintenanceItem> get loadedTemplates => _loadedTemplates;

  /// 当前阶段（派生值，不存储）：第一步表单 / 模板加载中 / 项目草稿就绪。
  AddCarWizardStage get stage {
    final car = carDraft;
    if (car == null || editingCarDraft) {
      return AddCarWizardStage.form;
    }
    final items = itemDrafts;
    if (items != null && itemModelKey == carModelKey(car)) {
      return AddCarWizardStage.items;
    }
    return AddCarWizardStage.loading;
  }

  /// 第一步"下一步"：记住车辆草稿进入第二步。模板的加载/缓存归注入的
  /// [loadTemplate]（family 按车型键缓存、专属优先回退通用，ADR 0004），
  /// 同车型同动力直接复用已改过的草稿不重载。失败清掉车草稿、错误写进
  /// [errorText]（阶段回第一步）。
  Future<void> submitCarDraft(Car car) async {
    final key = carModelKey(car);
    final sameKey = itemModelKey == key && itemDrafts != null;
    carDraft = car;
    editingCarDraft = false;
    errorText = null;
    if (sameKey) {
      return;
    }
    try {
      final defaults = await loadTemplate(key);
      // 防御：等待期间车辆草稿已变（换车重提），丢弃这次过期结果。
      final current = carDraft;
      if (current == null || carModelKey(current) != key) {
        return;
      }
      itemModelKey = key;
      _loadedTemplates = defaults;
      itemDrafts = defaults
          .map((item) => maintenanceItemFromDefault(item, car.sync))
          .toList();
    } catch (error) {
      // 失败退回第一步——但只在还在等这次结果时：等待中已换草稿的话，
      // 错误由新一次提交自己报，这里不动状态。
      final current = carDraft;
      if (current == null || carModelKey(current) == key) {
        carDraft = null;
        errorText = friendlyError(error);
      }
    }
  }

  /// 第二步"上一步"：回到第一步表单（车辆/项目草稿都保留）。
  void returnToCarStep() {
    editingCarDraft = true;
  }

  /// 「至少保留一个启用项目」被拒文案：与仓库侧兜底错误（lunio_repository
  /// 抛的 typed 错误）同一口径。
  static const String _lastEnabledItemErrorText = '至少保留一个可用保养项目';

  /// 草稿列表"编辑"：按对象身份（identical）替换那一条草稿。替换不改
  /// 变启用数量（enabled 由启停管），恒成功返回 null。仅第二步可调
  /// （itemDrafts 未转出时静默不动）。
  String? editDraft(MaintenanceItem original, MaintenanceItem next) {
    final items = itemDrafts;
    if (items == null) {
      return null;
    }
    itemDrafts = [
      for (final current in items)
        if (identical(current, original)) next else current,
    ];
    return null;
  }

  /// 草稿列表"启停"：停用最后一个启用项时拒绝（返回提示文案、列表不
  /// 变），启用永远放行。仅第二步可调（itemDrafts 未转出时静默不动）。
  String? toggleDraft(MaintenanceItem item) {
    final items = itemDrafts;
    if (items == null) {
      return null;
    }
    final nextEnabled = !item.enabled;
    if (!nextEnabled &&
        !items.any(
          (current) => current.enabled && !identical(current, item),
        )) {
      return _lastEnabledItemErrorText;
    }
    itemDrafts = [
      for (final current in items)
        if (identical(current, item))
          current.copyWith(enabled: nextEnabled)
        else
          current,
    ];
    return null;
  }

  /// 草稿列表"删除"：删完没有启用项时拒绝（同启停守卫）。仅第二步可调
  /// （itemDrafts 未转出时静默不动）。
  String? removeDraft(MaintenanceItem item) {
    final items = itemDrafts;
    if (items == null) {
      return null;
    }
    final nextItems =
        items.where((current) => !identical(current, item)).toList();
    if (!nextItems.any((current) => current.enabled)) {
      return _lastEnabledItemErrorText;
    }
    itemDrafts = nextItems;
    return null;
  }

  /// 草稿列表追加一条（"新增"表单确认后；sheet 交互留在 widget）。
  void addDraft(MaintenanceItem item) {
    itemDrafts = [...?itemDrafts, item];
  }

  /// 恢复默认项目：把勾选的模板项转成草稿追加（勾选 sheet 留在 widget）。
  void restoreDefaults(Iterable<VehicleDefaultMaintenanceItem> selected) {
    final car = carDraft;
    if (car == null) {
      return;
    }
    itemDrafts = [
      ...?itemDrafts,
      for (final item in selected) maintenanceItemFromDefault(item, car.sync),
    ];
  }
}

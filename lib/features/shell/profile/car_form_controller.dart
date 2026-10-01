// 车辆基础信息表单的决策体控制器（2026-10-01 收编）：添加车辆向导
// 第一步与编辑车辆 sheet 共用的那张表单里，全部字段决策的唯一实现。
//
// 职责：
//   1. 字段态：品牌车型选中项、动力类型、当前里程、上路日期、油箱容积；
//   2. 初始态（构造一处）：新增默认选目录第一项 + 目录推荐动力类型 +
//      里程 "0" + 容积空 + 上路日期 = 生效今天；编辑（含向导"上一步"
//      带回的无 id 草稿）回填 initialCar 的字段值；
//   3. 换车型时动力类型重置为该车型的目录推荐值（自定义车型无推荐值
//      回燃油，用户可再改）；
//   4. 校验：里程非负整数；容积选填，规则本体在 FuelRules
//      .validateTankCapacity（1–999、最多四位小数），这里只做表单侧的
//      中文文案翻译；
//   5. 提交载荷构造：编辑保留 id 与身份字段（品牌/车型/动力类型），
//      sync 状态位按新增/编辑取 pendingCreate/pendingUpdate。
//
// 在 App 中的位置：只被 add_car_wizard.dart 的 AddCarForm（向导第一步
// + 编辑车辆复用）使用。≈ Java Web 里表单页抽出来的 BackingBean
// （同 RecordFormController / FuelRecordFormController / 
// AddCarWizardController 先例）：持有输入控件状态与流转决策，widget 只做
// 渲染并把事件转接进来；事件方法只改状态不触发重建，widget 在事件返回
// 后自行 setState。
//
// 与两道既有 seam 的边界：
//   - ADR 0016 表单运行时：本类不持有 FormSheetHandle、不碰 pop/toast/
//     saving，提交走 handle.submit 还是 handle.run（编辑关场 vs 向导
//     推进）由 widget 按 closeOnSubmit 分发；行内错误经注入的
//     reportError 写 handle；
//   - ADR 0007 动作层：本类只产出提交载荷，写库（createCar/updateCar）
//     的接线留在入口函数。
// 编辑车辆目录为空的兜底假选项是装载期数据决策，也留在入口函数
// （vehicles.dart 的 showEditCarSheet）——本类只收算好的目录清单。
// 日期选择器的实现与文案是 UI 决策，经 [CarFormUi] 注入；日期边界
// （1990-01-01 ~ 生效今天+365）由本类算好传给注入的 picker。
import 'package:flutter/material.dart';

import '../../../core/date/local_date.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/powertrain_type.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_model.dart';
import '../../../domain/rules/fuel_rules.dart';

/// 车辆基础信息表单的 UI 答案注入点：控制器驱动日期选择时需要用户
/// 交互的答案。实现与文案留在 widget 侧（选择器是 UI 决策，本类不碰
/// BuildContext），先例：RecordFormUi / FuelRecordFormUi 的 pickDate。
class CarFormUi {
  const CarFormUi({required this.pickDate});

  /// 弹日期选择器：[initial] = 当前选中日期；[first]/[last] = 合法边界
  /// （控制器按"1990-01-01 起、生效今天+365 止"算好传入，边界判定归
  /// 控制器）。返回 null = 用户取消。
  final Future<LocalDate?> Function(
    LocalDate initial,
    LocalDate first,
    LocalDate last,
  )
  pickDate;
}

/// 车辆基础信息表单控制器（职责与边界见文件头）。
///
/// 接口约定：事件方法（selectModel / setPowertrain / pickRoadDate /
/// submitPayload）只改状态与经 [CarFormUi]/reportError 与外界交互，
/// 不触发重建——widget 在事件返回后自行 setState。渲染所需的派生状态
/// 经 selectedBrand / selectedModel / selectedPowertrain / roadDate /
/// 两个输入框 controller 暴露。
class CarFormController {
  CarFormController({
    required this.vehicleModels,
    required this.today,
    Car? initialCar,
    required this.ui,
    required this.reportError,
    DateTime Function()? now,
  }) : initialCar = initialCar,
       _now = now ?? DateTime.now,
       mileageController = TextEditingController(
         text: initialCar?.currentMileageKm.toString() ?? '0',
       ),
       capacityController = TextEditingController(
         text: _capacityInputText(initialCar?.tankCapacityLiters),
       ) {
    // 初始态唯一实现点：编辑（含向导"上一步"带回的无 id 草稿）回填
    // initialCar 的字段值，新增默认选目录第一项（老目录时代写死的
    // "本田 思域（燃油版）"已随 ADR 0003 废弃）。
    selectedBrand = initialCar?.brand ?? vehicleModels.first.brand;
    selectedModel =
        initialCar?.model ?? _firstModelOfBrand(vehicleModels, selectedBrand);
    selectedPowertrain =
        initialCar?.powertrainType ??
        _recommendedPowertrain(vehicleModels, selectedBrand, selectedModel);
    roadDate = initialCar?.roadDate ?? today;
  }

  /// 车型目录（只读数据，装载期由入口函数传入；编辑车辆目录为空时
  /// 入口已拼好兜底假选项，本类不重复兜底）。
  final List<VehicleModel> vehicleModels;

  /// 生效今天（手动日期覆盖后的应用日期）：新增默认上路日期与日期
  /// 上界（+365 天）的基准。
  final LocalDate today;

  /// 编辑目标车辆（null = 新增）。向导"上一步"带回的草稿没有 id——
  /// 按"字段可改"的新增分支处理，但字段值从草稿回填。
  final Car? initialCar;

  /// UI 答案注入点（先例：RecordFormUi.pickDate）：日期选择器的实现与
  /// 文案在 widget 侧。
  final CarFormUi ui;

  /// 行内错误注入点：控制器把校验错误的文案写到 widget 侧的
  /// handle.setFormError（ADR 0016 错误统一在把手上显示）。
  final void Function(String? message) reportError;

  /// 当前时刻注入（默认 DateTime.now）：提交载荷的 sync.updatedAt 与
  /// now 解耦，单测可固定时刻断言。
  final DateTime Function() _now;

  /// 选中的品牌（新增态；编辑态品牌锁定在 initialCar，本字段不被读）。
  /// late：构造体里的初始态赋值（见构造函数）必然先于任何读取。
  late String selectedBrand;

  /// 选中的车型（同上）。
  late String selectedModel;

  /// 选中的动力类型。选车型时重置为该车型的目录推荐值，用户可改；
  /// 自定义车型没有推荐值，从燃油开始。
  late PowertrainType selectedPowertrain;

  /// 里程输入框（公里，非负整数）。
  final TextEditingController mileageController;

  /// 油箱容积输入框（升，选填）。
  final TextEditingController capacityController;

  /// 上路日期（新增默认 = 生效今天，编辑 = 原日期）。
  late LocalDate roadDate;

  /// 编辑模式判据：initialCar 有 id 才是编辑（品牌车型与动力类型为
  /// 身份字段锁定只读）；无 id 的向导草稿走新增分支。
  bool get isEditing => initialCar?.id != null;

  /// 换车型（选择器 sheet 或自定义输入确认后）：赋值新品牌车型，并把
  /// 动力类型重置为该车型的目录推荐值——推荐值只用于预选，用户可再改。
  void selectModel(String brand, String model) {
    selectedBrand = brand;
    selectedModel = model;
    selectedPowertrain = _recommendedPowertrain(vehicleModels, brand, model);
  }

  /// 切换动力类型 chip：纯赋值。
  void setPowertrain(PowertrainType value) {
    selectedPowertrain = value;
  }

  /// 点「上路日期」：弹注入的日期选择器，边界（1990-01-01 起、生效
  /// 今天+365 止——预登记的新车允许最多提前一年）由本类算好传给
  /// picker；用户取消不动。
  Future<void> pickRoadDate() async {
    final picked = await ui.pickDate(
      roadDate,
      const LocalDate(1990, 1, 1),
      LocalDate.fromDateTime(today.toDateTime().add(const Duration(days: 365))),
    );
    if (picked == null) {
      return;
    }
    roadDate = picked;
  }

  /// 「保存车辆 / 下一步」的提交载荷：里程非负整数校验 → 容积校验
  /// （选填，1–999、最多四位小数，规则本体在 FuelRules）失败时报行内
  /// 错误（中文文案）并返回 null；成功时构造 [Car]——编辑保留 id 与
  /// 身份字段（品牌/车型/动力类型）、容积空 = null（选填语义）、sync
  /// 状态位按新增/编辑取 pendingCreate/pendingUpdate、updatedAt 经注入
  /// 的 now。写库由 widget 经 handle → 动作层完成，本类不碰。
  ///
  /// 输入框本身带数字键盘约束（里程非负整数、容积最多四位小数），
  /// 这里兜的是程序态输入与粘贴。
  Car? submitPayload() {
    final mileage = int.tryParse(mileageController.text);
    if (mileage == null || mileage < 0) {
      reportError('当前里程必须是非负整数');
      return null;
    }
    final capacityText = capacityController.text.trim();
    double? tankCapacity;
    if (capacityText.isNotEmpty) {
      final parsed = double.tryParse(capacityText);
      if (parsed == null || !_isValidTankCapacity(parsed)) {
        reportError('油箱容积需在 1–999 升之间，最多四位小数');
        return null;
      }
      tankCapacity = parsed;
    }
    final initialCar = this.initialCar;
    return Car(
      id: initialCar?.id,
      // 编辑模式身份字段锁定：品牌/车型/动力类型一律取 initialCar 的
      // 原值（表单里对应行只读，取选中值仅为新增分支）。
      brand: isEditing ? initialCar!.brand : selectedBrand,
      model: isEditing ? initialCar!.model : selectedModel,
      powertrainType: isEditing
          ? initialCar!.powertrainType
          : selectedPowertrain,
      currentMileageKm: mileage,
      roadDate: roadDate,
      tankCapacityLiters: tankCapacity,
      sync: SyncMetadata(
        status: isEditing ? SyncStatus.pendingUpdate : SyncStatus.pendingCreate,
        updatedAt: _now(),
      ),
    );
  }

  /// 释放全部输入控件（widget dispose 时调用）。
  void dispose() {
    mileageController.dispose();
    capacityController.dispose();
  }

  /// 容积回填文本：整数不带小数位（55），非整数按原样（64.5、55.1234），
  /// 没填（null）空串（保留"选填"语义）。
  static String _capacityInputText(double? liters) {
    if (liters == null) {
      return '';
    }
    return liters % 1 == 0 ? liters.toStringAsFixed(0) : liters.toString();
  }

  /// 品牌下的第一个车型（新增默认选目录第一项的第二步：先取目录
  /// 第一项的品牌，再取该品牌下第一个车型）。品牌在目录中无车型时
  /// 不会发生（目录数据保证品牌都至少有一个车型）。
  static String _firstModelOfBrand(
    List<VehicleModel> models,
    String? brand,
  ) {
    final target = brand ?? models.first.brand;
    for (final candidate in models) {
      if (candidate.brand == target) {
        return candidate.model;
      }
    }
    return models.first.model;
  }

  /// 目录推荐动力类型：按（品牌, 车型）查目录；自定义车型不在目录里，
  /// 没有推荐值，默认燃油。
  static PowertrainType _recommendedPowertrain(
    List<VehicleModel> models,
    String brand,
    String model,
  ) {
    for (final candidate in models) {
      if (candidate.brand == brand && candidate.model == model) {
        return candidate.template;
      }
    }
    return PowertrainType.fuel;
  }

  /// 容积合法性：规则本体在 FuelRules.validateTankCapacity（抛
  /// ArgumentError 表非法），这里翻译成布尔供校验阶梯用。
  static bool _isValidTankCapacity(double liters) {
    try {
      FuelRules.validateTankCapacity(liters);
      return true;
    } on ArgumentError {
      return false;
    }
  }
}

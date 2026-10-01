// 加油记录表单的决策体控制器（ADR 0015 五项输入，2026-10-01 收编）：
// 新增/编辑加油记录 sheet 里全部业务决策与字段状态的唯一实现。
//
// 职责：
//   1. 字段态：加油日期、油品胶囊选中项、单价/应付/实付三个输入框；
//   2. 单价回填优先级：编辑值 > 预填生效价 > 空，收在构造函数一处；
//      预填只在构造时生效一次（之后切油品不重算，不覆盖用户输入）；
//   3. "同应付"快捷回填的守卫：应付为空/非法输入时不动；
//   4. 三条金额校验阶梯：单价 > 0、应付 > 0、实付填了必须非负
//      （与实体 validate 同口径，提前给中文行内错误）；
//   5. 提交载荷构造：三个金额经全表单唯一解析接缝 parseMoneyCents
//      元→分四舍五入（与保养记录费用算链同一份实现，2026-10-01 收编）、
//      实付空 = null（选填语义）、sync 状态位按新增/编辑取
//      pendingCreate/pendingUpdate。
//
// 在 App 中的位置：只被 fuel_records_card.dart 的 FuelRecordForm 使用。
// ≈ Java Web 里表单页抽出来的 BackingBean（同 RecordFormController /
// RecordCostFormController / AddCarWizardController 先例）：持有输入控件
// 状态与流转决策，widget 只做渲染并把事件转接进来；事件方法只改状态
// 不触发重建，widget 在事件返回后自行 setState。
//
// 与两道既有 seam 的边界：
//   - ADR 0016 表单运行时：本类不持有 FormSheetHandle、不碰 pop/toast/
//     saving；行内错误经注入的 reportError 写 handle（生命周期守卫留在
//     widget 侧的注入闭包）；
//   - ADR 0007 动作层：本类只产出提交载荷，写库（saveFuelRecord）的
//     接线留在入口函数。
// 预填值的获取（读油价域 provider 比对油品）是装载期数据决策，也留在
// 入口函数的 load 阶段——本类只收算好的 double? 值，不依赖 ref。
// 日期选择器的实现与文案是 UI 决策，经 [FuelRecordFormUi] 注入；日期
// 边界（上路日期起、上限今天）由本类算好传给注入的 picker。
import 'package:flutter/material.dart';

import '../../../core/date/local_date.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/fuel_price.dart';
import '../../../domain/entities/fuel_record.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../shared/formatters.dart';

/// 加油记录表单的 UI 答案注入点：控制器驱动日期选择时需要用户交互的
/// 答案。实现与文案留在 widget 侧（选择器是 UI 决策，本类不碰
/// BuildContext）。
class FuelRecordFormUi {
  const FuelRecordFormUi({required this.pickDate});

  /// 弹日期选择器：[initial] = 当前选中日期；[first]/[last] = 合法边界
  /// （控制器按"上路日期起、上限今天"算好传入，边界判定归控制器）。
  /// 返回 null = 用户取消。
  final Future<LocalDate?> Function(
    LocalDate initial,
    LocalDate first,
    LocalDate last,
  )
  pickDate;
}

/// 加油记录表单控制器（职责与边界见文件头）。
///
/// 接口约定：事件方法（setGrade / copyPayableToActual / pickRecordDate /
/// submitPayload）只改状态与经 [FuelRecordFormUi]/reportError 与外界
/// 交互，不触发重建——widget 在事件返回后自行 setState。渲染所需的
/// 派生状态经 recordDate / grade / 三个 controller 暴露。
class FuelRecordFormController {
  FuelRecordFormController({
    required this.car,
    required this.today,
    FuelRecord? record,
    double? prefillUnitPrice,
    required this.ui,
    required this.reportError,
    DateTime Function()? now,
  }) : record = record,
       _now = now ?? DateTime.now,
       // 新增默认日期 = 生效今天、油品默认 92#（与表单胶囊一致）。
       recordDate = record?.date ?? today,
       grade = record?.grade ?? FuelGrade.gasoline92,
       // 单价回填优先级（唯一实现点）：编辑值 > 预填生效价 > 空。
       // toStringAsFixed(2) 与数字键盘两位小数上限一致（8.1 → "8.10"）；
       // 预填只在构造时应用一次——之后切油品胶囊不会重算（见 setGrade），
       // 避免覆盖用户已输入的价格。
       unitPriceController = TextEditingController(
         text: record != null
             ? formatMoneyText(record.unitPriceCents)
             : prefillUnitPrice?.toStringAsFixed(2) ?? '',
       ),
       payableController = TextEditingController(
         text: record == null ? '' : formatMoneyText(record.payableCents),
       ),
       // 实付没填（null）回填空串，保留"选填"语义。
       actualController = TextEditingController(text: _actualText(record));

  /// 所属车辆（载荷的 carId 与日期下界取它）。
  final Car car;

  /// 生效今天（手动日期覆盖后的应用日期）：新增默认日期与日期上界。
  final LocalDate today;

  /// 编辑目标记录（null = 新增）。
  final FuelRecord? record;

  /// UI 答案注入点（先例：RecordFormUi.pickDate）：日期选择器的实现与
  /// 文案在 widget 侧。
  final FuelRecordFormUi ui;

  /// 行内错误注入点：控制器把校验错误的文案写到 widget 侧的
  /// handle.setFormError（ADR 0016 错误统一在把手上显示）。
  final void Function(String? message) reportError;

  /// 当前时刻注入（默认 DateTime.now）：提交载荷的 sync.updatedAt 与
  /// now 解耦，单测可固定时刻断言。
  final DateTime Function() _now;

  /// 加油日期（新增默认 = 生效今天，编辑 = 原日期）。
  LocalDate recordDate;

  /// 油品胶囊选中项（新增默认 92#）。
  FuelGrade grade;

  /// 单价输入框（元/升，两位小数）。
  final TextEditingController unitPriceController;

  /// 应付金额输入框（元，必填）。
  final TextEditingController payableController;

  /// 实付金额输入框（元，选填——空串 = 未填）。
  final TextEditingController actualController;

  bool get isEditing => record != null;

  /// 切换油品胶囊：纯赋值。单价预填只在构造时生效一次，这里刻意不
  /// 重算预填（换油品不读生效价），避免覆盖用户已输入的价格。
  void setGrade(FuelGrade value) {
    grade = value;
  }

  /// 点中间箭头「同应付」：把应付金额一键回填进实付。应付为空或非法
  /// 输入时不动（守卫）——非法值复制过去只会把错误从一格带到另一格。
  void copyPayableToActual() {
    final text = payableController.text;
    if (text.isEmpty || double.tryParse(text) == null) {
      return;
    }
    actualController.text = text;
  }

  /// 点「加油日期」：弹注入的日期选择器，边界（上路日期起、**上限
  /// 今天**，不能未来，2026-09-22 拍板，与保养记录同规则）由本类算好
  /// 传给 picker；用户取消不动。没有同日查重——同车同日多箱合法
  /// （ADR 0014/0015）。
  Future<void> pickRecordDate() async {
    final picked = await ui.pickDate(recordDate, car.roadDate, today);
    if (picked == null) {
      return;
    }
    recordDate = picked;
  }

  /// 「保存」的提交载荷：三条金额校验阶梯失败时报行内错误（中文文案）
  /// 并返回 null；成功时构造 [FuelRecord]——三个金额经全表单唯一解析
  /// 接缝 parseMoneyCents 元→分四舍五入（校验也站在分上做，与实体
  /// validate 同口径）、实付空 = null（选填语义，留空存无优惠）、sync
  /// 状态位按新增/编辑取 pendingCreate/pendingUpdate、updatedAt 经注入
  /// 的 now。容积由实体按应付÷单价自算（预留字段）。写库由 widget 经
  /// handle.submit → 动作层完成，本类不碰。
  FuelRecord? submitPayload() {
    // 三个金额一次解析到位（元→分，trim/四舍五入/空与非法 = null 只有
    // parseMoneyCents 这一份实现）；实付空/非法 → null 即"未填"。
    final unitPriceCents = parseMoneyCents(unitPriceController.text);
    final payableCents = parseMoneyCents(payableController.text);
    final actualCents = parseMoneyCents(actualController.text);
    if (unitPriceCents == null || unitPriceCents <= 0) {
      reportError('单价必须大于 0');
      return null;
    }
    if (payableCents == null || payableCents <= 0) {
      reportError('应付金额必须大于 0');
      return null;
    }
    if (actualCents != null && actualCents < 0) {
      reportError('实付金额必须是非负数字');
      return null;
    }
    return FuelRecord(
      id: record?.id,
      carId: car.id!,
      date: recordDate,
      grade: grade,
      unitPriceCents: unitPriceCents,
      payableCents: payableCents,
      actualCents: actualCents,
      sync: SyncMetadata(
        status: isEditing ? SyncStatus.pendingUpdate : SyncStatus.pendingCreate,
        updatedAt: _now(),
      ),
    );
  }

  /// 释放全部输入控件（widget dispose 时调用）。
  void dispose() {
    unitPriceController.dispose();
    payableController.dispose();
    actualController.dispose();
  }

  /// 实付回填文本：没填（null）回空串，保留"选填"语义（构造初始化用
  /// 的纯函数，先落本地再判空——初始化列表里不方便做类型提升）。
  static String _actualText(FuelRecord? record) {
    final actual = record?.actualCents;
    return actual == null ? '' : formatMoneyText(actual);
  }
}

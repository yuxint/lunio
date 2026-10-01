// 车辆基础信息表单控制器（CarFormController）的单元测试。
//
// 直接打控制器接口（不用 pump widget），锁死从 AddCarFormState 收编出来的
// 全部决策（2026-10-01，决策与校验归控制器、日期选择器实现归 widget）：
//  - 初始态三条分支：新增默认（目录第一项 + 推荐动力类型 + 里程 "0" +
//    容积空 + 上路日期 = 生效今天）、编辑回填（身份字段 + 里程 + 容积
//    整数/非整数格式）、向导"上一步"带回的无 id 草稿（新增分支回填）；
//  - 换车型重置推荐动力类型：目录内车型取推荐值，自定义车型回燃油；
//  - 里程校验：非整数 / 负数报中文行内错误、不产出载荷；
//  - 容积校验：规则本体在 FuelRules（1–999、最多四位小数），这里锁
//    表单侧文案与"空 = 选填放行"；
//  - 新增/编辑提交载荷：编辑保留 id 与身份字段、容积空 = null（选填
//    语义）、sync 状态位 pendingCreate/pendingUpdate、updatedAt 用注入
//    时钟；
//  - 日期边界：注入的日期选择器收到 first = 1990-01-01、last = 生效
//    今天+365（预登记最多提前一年）。
//
// 表单行为零变化的 widget 侧回归在 test/widget/vehicles_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/powertrain_type.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/entities/vehicle_model.dart';
import 'package:lunio/features/shell/profile/car_form_controller.dart';

import '../helpers/builders.dart';

/// 假日期选择器：记录注入收到的三参（initial/first/last），返回预设
/// 答案（默认 null = 用户取消）。
class FakeDatePicker {
  LocalDate? answer;
  LocalDate? initialArg;
  LocalDate? firstArg;
  LocalDate? lastArg;

  Future<LocalDate?> call(
    LocalDate initial,
    LocalDate first,
    LocalDate last,
  ) async {
    initialArg = initial;
    firstArg = first;
    lastArg = last;
    return answer;
  }
}

/// 测试夹具：装配控制器 + 行内错误捕获 + 假日期选择器 + 固定时钟。
class CarFormHarness {
  CarFormHarness({Car? initialCar}) {
    controller = CarFormController(
      vehicleModels: catalog,
      today: today,
      initialCar: initialCar,
      ui: CarFormUi(pickDate: picker.call),
      reportError: (message) => reportedError = message,
      now: () => fixedNow,
    );
  }

  late final CarFormController controller;
  final FakeDatePicker picker = FakeDatePicker();

  /// 行内错误捕获（控制器校验失败时只写非空文案）。
  String? reportedError;

  /// 注入的固定时钟：sync.updatedAt 的断言值。
  final DateTime fixedNow = DateTime(2026, 6, 1, 8, 30);
}

/// 受控常量：生效今天与测试目录。
const today = LocalDate(2026, 5, 19);

/// 测试目录：第一项奥迪A3（燃油）——新增默认选中它；比亚迪秦PLUS DM-i
/// 推荐插混（换车型重置推荐值的断言素材）、蔚来 ET5 推荐纯电。
final List<VehicleModel> catalog = [
  VehicleModel(
    brand: '奥迪',
    model: '奥迪A3',
    template: PowertrainType.fuel,
    sortOrder: 1,
    sync: testSync,
  ),
  VehicleModel(
    brand: '比亚迪',
    model: '秦PLUS DM-i',
    template: PowertrainType.plugIn,
    sortOrder: 2,
    sync: testSync,
  ),
  VehicleModel(
    brand: '蔚来',
    model: 'ET5',
    template: PowertrainType.electric,
    sortOrder: 3,
    sync: testSync,
  ),
];

/// 编辑目标车辆（defaultCar 的口径 + 直参 id——Car.copyWith 不开放 id
/// 替换，入库态车辆走实体构造器）。
final editingCar = Car(
  id: 77,
  brand: '本田',
  model: '22款思域',
  currentMileageKm: 10000,
  roadDate: LocalDate(2023, 8, 12),
  sync: testSync,
);

void main() {
  test('new form defaults to first catalog entry with recommended powertrain', () {
    final harness = CarFormHarness();

    expect(harness.controller.isEditing, isFalse);
    // 新增默认：目录第一项（品牌 + 该品牌第一个车型）+ 推荐动力类型。
    expect(harness.controller.selectedBrand, '奥迪');
    expect(harness.controller.selectedModel, '奥迪A3');
    expect(harness.controller.selectedPowertrain, PowertrainType.fuel);
    // 里程默认 "0"、容积空（选填）、上路日期 = 生效今天。
    expect(harness.controller.mileageController.text, '0');
    expect(harness.controller.capacityController.text, '');
    expect(harness.controller.roadDate, today);
  });

  test('edit form backfills identity fields, mileage and capacity text', () {
    final harness = CarFormHarness(
      initialCar: editingCar.copyWith(tankCapacityLiters: 55),
    );

    expect(harness.controller.isEditing, isTrue);
    // 身份字段与里程/日期从原车回填（本田思域不在测试目录里也照样回显）。
    expect(harness.controller.selectedBrand, '本田');
    expect(harness.controller.selectedModel, '22款思域');
    expect(harness.controller.selectedPowertrain, PowertrainType.fuel);
    expect(harness.controller.mileageController.text, '10000');
    expect(harness.controller.roadDate, const LocalDate(2023, 8, 12));
    // 容积整数不带小数位（55，不是 55.0）。
    expect(harness.controller.capacityController.text, '55');

    // 非整数容积按原样回填（64.5）。
    final fractional = CarFormHarness(
      initialCar: editingCar.copyWith(tankCapacityLiters: 64.5),
    );
    expect(fractional.controller.capacityController.text, '64.5');

    // 容积没填回空串（选填语义）。
    final empty = CarFormHarness(initialCar: editingCar);
    expect(empty.controller.capacityController.text, '');
  });

  test('wizard draft without id backfills fields but stays in new branch', () {
    // 向导"上一步"带回的草稿没有 id：isEditing 为 false（身份字段可改），
    // 但字段值从草稿回填（保留用户已做的选择）。
    final draft = defaultCar(
      brand: '蔚来',
      model: 'ET5',
      currentMileageKm: 3000,
      powertrainType: PowertrainType.electric,
      tankCapacityLiters: 75,
    );
    final harness = CarFormHarness(initialCar: draft);

    expect(harness.controller.isEditing, isFalse);
    expect(harness.controller.selectedBrand, '蔚来');
    expect(harness.controller.selectedModel, 'ET5');
    expect(harness.controller.selectedPowertrain, PowertrainType.electric);
    expect(harness.controller.mileageController.text, '3000');
    expect(harness.controller.capacityController.text, '75');
  });

  test('selecting a catalog model resets powertrain to its recommendation', () {
    final harness = CarFormHarness();

    // 换到推荐插混的车型：动力类型重置为推荐值。
    harness.controller.selectModel('比亚迪', '秦PLUS DM-i');
    expect(harness.controller.selectedBrand, '比亚迪');
    expect(harness.controller.selectedModel, '秦PLUS DM-i');
    expect(harness.controller.selectedPowertrain, PowertrainType.plugIn);

    // 换到推荐纯电的车型：再重置。
    harness.controller.selectModel('蔚来', 'ET5');
    expect(harness.controller.selectedPowertrain, PowertrainType.electric);

    // 用户手改后不随重选丢失——setPowertrain 是纯赋值。
    harness.controller.setPowertrain(PowertrainType.extendedRange);
    expect(harness.controller.selectedPowertrain, PowertrainType.extendedRange);

    // 自定义车型（目录外）没有推荐值，重置回燃油。
    harness.controller.selectModel('雪佛兰', '科鲁泽');
    expect(harness.controller.selectedPowertrain, PowertrainType.fuel);
  });

  test('validation rejects missing or non-integer mileage', () {
    final harness = CarFormHarness();

    // 非整数输入（程序态输入兜底，数字键盘打不出来）。
    harness.controller.mileageController.text = 'abc';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '当前里程必须是非负整数');

    // 负数同理。
    harness.controller.mileageController.text = '-1';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '当前里程必须是非负整数');
  });

  test('validation rejects out-of-range or over-precise capacity', () {
    final harness = CarFormHarness();

    // 低于下限（1 升起）。
    harness.controller.capacityController.text = '0.5';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '油箱容积需在 1–999 升之间，最多四位小数');

    // 超上限。
    harness.controller.capacityController.text = '1000';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '油箱容积需在 1–999 升之间，最多四位小数');

    // 小数位超过四位（规则本体在 FuelRules，这里锁表单侧文案）。
    harness.controller.capacityController.text = '55.12345';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '油箱容积需在 1–999 升之间，最多四位小数');

    // 清空容积 = 选填放行，错误不再报（合法空态）。
    harness.controller.capacityController.text = '';
    expect(harness.controller.submitPayload(), isNotNull);
  });

  test('new payload uses selection and pendingCreate with injected now', () async {
    final harness = CarFormHarness();
    harness.controller.selectModel('比亚迪', '秦PLUS DM-i');
    harness.controller.setPowertrain(PowertrainType.hybrid);
    harness.controller.mileageController.text = '12000';
    harness.controller.capacityController.text = '48.5';
    harness.picker.answer = const LocalDate(2024, 1, 2);
    await harness.controller.pickRoadDate();

    final payload = harness.controller.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.id, isNull);
    // 用户手改的动力类型优先生效（selectModel 的推荐值被 setPowertrain 覆盖）。
    expect(payload.brand, '比亚迪');
    expect(payload.model, '秦PLUS DM-i');
    expect(payload.powertrainType, PowertrainType.hybrid);
    expect(payload.currentMileageKm, 12000);
    expect(payload.roadDate, const LocalDate(2024, 1, 2));
    expect(payload.tankCapacityLiters, 48.5);
    // 新增状态位 + 注入时钟。
    expect(payload.sync.status, SyncStatus.pendingCreate);
    expect(payload.sync.updatedAt, harness.fixedNow);

    // 里程 0 是合法值（新车）。
    harness.controller.mileageController.text = '0';
    expect(harness.controller.submitPayload()!.currentMileageKm, 0);
  });

  test('edit payload keeps id and identity fields from original car', () {
    final harness = CarFormHarness(initialCar: editingCar);

    // 编辑态下用户只能改里程/日期/容积；即便选中态被外部动过（正常
    // 渲染下身份行只读不可达），载荷的身份字段也锁定取 initialCar 原值。
    harness.controller.selectModel('蔚来', 'ET5');
    harness.controller.mileageController.text = '60000';
    harness.controller.capacityController.text = '55';

    final payload = harness.controller.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.id, 77);
    expect(payload.brand, '本田');
    expect(payload.model, '22款思域');
    expect(payload.powertrainType, PowertrainType.fuel);
    expect(payload.currentMileageKm, 60000);
    expect(payload.roadDate, const LocalDate(2023, 8, 12));
    expect(payload.tankCapacityLiters, 55);
    expect(payload.sync.status, SyncStatus.pendingUpdate);
    expect(payload.sync.updatedAt, harness.fixedNow);

    // 容积清空再保存：null 落库（选填，清掉已填值是合法操作）。
    harness.controller.capacityController.text = '';
    final cleared = harness.controller.submitPayload();
    expect(cleared!.tankCapacityLiters, isNull);
  });

  test('date picker receives 1990-to-today-plus-365 bounds; cancel keeps date', () async {
    final harness = CarFormHarness(initialCar: editingCar);

    // 用户取消（假 picker 默认 null）：日期不动。
    await harness.controller.pickRoadDate();
    expect(harness.controller.roadDate, const LocalDate(2023, 8, 12));
    // 边界判定归控制器：first = 1990-01-01、last = 生效今天+365、
    // 初始 = 当前选中。
    expect(harness.picker.initialArg, const LocalDate(2023, 8, 12));
    expect(harness.picker.firstArg, const LocalDate(1990, 1, 1));
    expect(harness.picker.lastArg, const LocalDate(2027, 5, 19));

    // 选中新日期：落定到字段（重建由 widget 负责）。
    harness.picker.answer = const LocalDate(2024, 6, 1);
    await harness.controller.pickRoadDate();
    expect(harness.controller.roadDate, const LocalDate(2024, 6, 1));
  });
}

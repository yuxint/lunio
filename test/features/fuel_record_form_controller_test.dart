// 加油记录表单控制器（FuelRecordFormController）的单元测试。
//
// 直接打控制器接口（不用 pump widget），锁死从表单 State 收编出来的
// 全部决策（2026-10-01，决策与校验归控制器、日期选择器实现归 widget）：
//  - 单价回填三种优先级：编辑值 > 预填生效价 > 空；
//  - 预填只在构造时生效一次：切油品胶囊不重算、不覆盖已输入单价；
//  - "同应付"快捷回填：应付为空/非法时不动，合法时整串复制；
//  - 三条金额校验阶梯：单价 > 0、应付 > 0、实付填了必须非负
//    （失败报中文行内错误、不产出载荷）；
//  - 新增/编辑提交载荷：金额元→分四舍五入、实付空 = null（选填
//    语义）、sync 状态位 pendingCreate/pendingUpdate、updatedAt 用
//    注入时钟；
//  - 日期边界：注入的日期选择器收到 first = 上路日期、last = 生效
//    今天（"不能未来"的边界判定归控制器）。
//
// 金额合法性本体在 FuelRecord.validate（实体构造自校验），这里只锁
// 控制器的输入态编排与中文文案；表单行为零变化的 widget 侧回归在
// test/widget/fuel_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/fuel_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/fuel/fuel_record_form_controller.dart';

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
class FuelFormHarness {
  FuelFormHarness({FuelRecord? record, double? prefillUnitPrice}) {
    controller = FuelRecordFormController(
      car: testCar,
      today: today,
      record: record,
      prefillUnitPrice: prefillUnitPrice,
      ui: FuelRecordFormUi(pickDate: picker.call),
      reportError: (message) => reportedError = message,
      now: () => fixedNow,
    );
  }

  late final FuelRecordFormController controller;
  final FakeDatePicker picker = FakeDatePicker();

  /// 行内错误捕获（控制器校验失败时只写非空文案）。
  String? reportedError;

  /// 注入的固定时钟：sync.updatedAt 的断言值。
  final DateTime fixedNow = DateTime(2026, 6, 1, 8, 30);
}

/// 受控常量：生效今天与测试车（defaultCar 的口径 + 直参 id——
/// Car.copyWith 不开放 id 替换，入库态车辆走实体构造器）。
const today = LocalDate(2026, 5, 19);
final testCar = Car(
  id: 77,
  brand: '本田',
  model: '22款思域',
  currentMileageKm: 10000,
  roadDate: LocalDate(2023, 8, 12),
  sync: testSync,
);

void main() {
  test('unit price backfill prefers edit value over prefill and empty', () {
    // 优先级 1/3：编辑态回填记录自己的单价，忽略预填值；应付/实付
    // 同步回填，实付没填回空串。
    final record = defaultFuelRecord(
      77,
      date: const LocalDate(2026, 5, 10),
      actualCents: 27000,
    ).copyWith(id: 512);
    final harness = FuelFormHarness(record: record, prefillUnitPrice: 7.61);

    expect(harness.controller.isEditing, isTrue);
    expect(harness.controller.unitPriceController.text, '8.15');
    expect(harness.controller.payableController.text, '300.00');
    expect(harness.controller.actualController.text, '270.00');
    expect(harness.controller.recordDate, const LocalDate(2026, 5, 10));
    expect(harness.controller.grade, FuelGrade.gasoline92);
  });

  test('new record prefills effective price when provided', () {
    // 优先级 2/3：新增 + 预填值 → toStringAsFixed(2) 两位小数（8.1 也会
    // 补成 8.10，与数字键盘精度一致）。
    final harness = FuelFormHarness(prefillUnitPrice: 7.61);

    expect(harness.controller.isEditing, isFalse);
    expect(harness.controller.unitPriceController.text, '7.61');
    expect(harness.controller.payableController.text, '');
    expect(harness.controller.actualController.text, '');
    // 新增默认：日期 = 生效今天、油品 = 92#。
    expect(harness.controller.recordDate, today);
    expect(harness.controller.grade, FuelGrade.gasoline92);

    final oneDecimal = FuelFormHarness(prefillUnitPrice: 8.1);
    expect(oneDecimal.controller.unitPriceController.text, '8.10');
  });

  test('new record without prefill starts with empty unit price', () {
    // 优先级 3/3：无预填 → 空串（油价卡油品与表单默认不一致时入口
    // 不传预填，见 showFuelRecordFormSheet 的 load 阶段）。
    final harness = FuelFormHarness();

    expect(harness.controller.unitPriceController.text, '');
  });

  test('prefill applies only once: switching grade never touches unit price', () {
    final harness = FuelFormHarness(prefillUnitPrice: 7.61);

    harness.controller.setGrade(FuelGrade.gasoline95);
    expect(harness.controller.grade, FuelGrade.gasoline95);
    // 切油品不重算预填，输入框保持构造时的值。
    expect(harness.controller.unitPriceController.text, '7.61');

    // 用户手改后的单价同样不被覆盖。
    harness.controller.unitPriceController.text = '8.00';
    harness.controller.setGrade(FuelGrade.diesel0);
    expect(harness.controller.grade, FuelGrade.diesel0);
    expect(harness.controller.unitPriceController.text, '8.00');
  });

  test('same-payable quick fill no-ops on empty or invalid payable', () {
    final harness = FuelFormHarness();

    // 应付为空：不动。
    harness.controller.copyPayableToActual();
    expect(harness.controller.actualController.text, '');

    // 应付非法（数字键盘外的程序态输入）：不动——复制过去只会把错误
    // 从一格带到另一格。
    harness.controller.payableController.text = 'abc';
    harness.controller.copyPayableToActual();
    expect(harness.controller.actualController.text, '');
  });

  test('same-payable quick fill copies valid payable text as-is', () {
    final harness = FuelFormHarness();

    harness.controller.payableController.text = '300';
    harness.controller.copyPayableToActual();
    // 整串原样复制（不在控制器里格式化，与收编前行为一致）。
    expect(harness.controller.actualController.text, '300');
  });

  test('validation ladder rejects missing or non-positive unit price', () {
    final harness = FuelFormHarness();
    harness.controller.payableController.text = '300';

    // 空 → 非法输入同一条错误。
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '单价必须大于 0');

    harness.controller.unitPriceController.text = '0';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '单价必须大于 0');
  });

  test('validation ladder rejects missing or non-positive payable', () {
    final harness = FuelFormHarness();
    harness.controller.unitPriceController.text = '8.15';

    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '应付金额必须大于 0');

    harness.controller.payableController.text = '0';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '应付金额必须大于 0');
  });

  test('validation ladder rejects negative actual when filled', () {
    final harness = FuelFormHarness();
    harness.controller.unitPriceController.text = '8.15';
    harness.controller.payableController.text = '300';
    harness.controller.actualController.text = '-1';

    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '实付金额必须是非负数字');
  });

  test('new payload rounds yuan to cents and keeps actual optional', () async {
    final harness = FuelFormHarness();
    harness.controller.unitPriceController.text = '8.15';
    // 300.005 元 → 30000.5 分 → 四舍五入 30001 分。
    harness.controller.payableController.text = '300.005';
    harness.controller.setGrade(FuelGrade.gasoline95);
    harness.picker.answer = const LocalDate(2026, 5, 1);
    await harness.controller.pickRecordDate();

    final payload = harness.controller.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.id, isNull);
    expect(payload.carId, 77);
    expect(payload.date, const LocalDate(2026, 5, 1));
    expect(payload.grade, FuelGrade.gasoline95);
    expect(payload.unitPriceCents, 815);
    expect(payload.payableCents, 30001);
    // 实付留空 = 无优惠存 null（选填语义）。
    expect(payload.actualCents, isNull);
    // 新增状态位 + 注入时钟。
    expect(payload.sync.status, SyncStatus.pendingCreate);
    expect(payload.sync.updatedAt, harness.fixedNow);
    // 容积 = 应付÷单价由实体自算（预留字段），控制器不掺和。
    expect(payload.volumeLiters, 36.81);

    // 实付填了 → 元转分四舍五入进载荷（270.5 → 27050）。
    harness.controller.actualController.text = '270.5';
    final discounted = harness.controller.submitPayload();
    expect(discounted!.actualCents, 27050);
  });

  test('edit payload keeps id, date and uses pendingUpdate', () {
    final record = defaultFuelRecord(
      77,
      date: const LocalDate(2026, 5, 10),
      actualCents: 27000,
    ).copyWith(id: 512);
    final harness = FuelFormHarness(record: record);

    // 编辑态字段即合法输入，直接产出载荷。
    final payload = harness.controller.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.id, 512);
    expect(payload.carId, 77);
    expect(payload.date, const LocalDate(2026, 5, 10));
    expect(payload.unitPriceCents, 815);
    expect(payload.payableCents, 30000);
    expect(payload.actualCents, 27000);
    expect(payload.sync.status, SyncStatus.pendingUpdate);
    expect(payload.sync.updatedAt, harness.fixedNow);
  });

  test('date picker receives road-date-to-today bounds; cancel keeps date', () async {
    final harness = FuelFormHarness();

    // 用户取消（假 picker 默认 null）：日期不动。
    await harness.controller.pickRecordDate();
    expect(harness.controller.recordDate, today);
    // 边界判定归控制器：first = 上路日期、last = 生效今天、初始 = 当前。
    expect(harness.picker.initialArg, today);
    expect(harness.picker.firstArg, const LocalDate(2023, 8, 12));
    expect(harness.picker.lastArg, today);

    // 选中新日期：落定到字段（重建由 widget 负责）。
    harness.picker.answer = const LocalDate(2026, 5, 1);
    await harness.controller.pickRecordDate();
    expect(harness.controller.recordDate, const LocalDate(2026, 5, 1));
  });
}

// 添加车辆向导草稿状态机（AddCarWizardController）的单元测试。
//
// 直接打控制器接口（不用 pump widget），锁死向导的完整迁移语义：
//  - 阶段派生：无草稿/上一步 = 第一步表单；草稿已交但模板未回 = 加载中；
//    模板转出 = 第二步就绪；
//  - 同车型键复用草稿不重载模板；换键（含换动力类型）重转；
//  - 模板失败回退第一步且错误可见；下一次提交清空错误；
//  - 竞态防御：等待中换车，过期的成功结果/过期失败都被丢弃；
//  - 提交校验"至少保留一个可用保养项目"；恢复默认合并、新增追加。
//
// 模板加载是注入点：测试用 Completer/fake 控制时序，不碰 Riverpod。
// 交互（sheet/pop/重建）留在 widget 层，由 widget 测试覆盖。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/powertrain_type.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/entities/vehicle_default_maintenance_item.dart';
import 'package:lunio/features/shell/profile/add_car_wizard.dart';
import 'package:lunio/features/shell/shared/formatters.dart';

VehicleDefaultMaintenanceItem makeTemplate(String name) {
  return VehicleDefaultMaintenanceItem(
    powertrainType: PowertrainType.fuel,
    itemName: name,
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 5000,
    timeIntervalMonths: 6,
    sortOrder: 0,
    sync: SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026, 9, 1),
    ),
  );
}

Car makeCar({
  String brand = '奥迪',
  String model = '奥迪A3',
  PowertrainType powertrain = PowertrainType.fuel,
}) {
  return Car(
    brand: brand,
    model: model,
    powertrainType: powertrain,
    currentMileageKm: 10000,
    roadDate: const LocalDate(2026, 1, 1),
    sync: SyncMetadata(
      status: SyncStatus.pendingCreate,
      updatedAt: DateTime(2026, 9, 1),
    ),
  );
}

MaintenanceItem makeDraft(String name, {bool enabled = true}) {
  return MaintenanceItem(
    carsId: 0,
    name: name,
    enabled: enabled,
    remindByMileage: true,
    remindByTime: true,
    sortOrder: 0,
    sync: SyncMetadata(
      status: SyncStatus.pendingCreate,
      updatedAt: DateTime(2026, 9, 1),
    ),
  );
}

void main() {
  final fuelTemplates = [makeTemplate('机油'), makeTemplate('汽油滤芯')];
  final bevTemplates = [makeTemplate('减速器油')];

  AddCarWizardController buildController({DefaultTemplateLoader? loader}) {
    return AddCarWizardController(
      loadTemplate: loader ?? (_) async => fuelTemplates,
    );
  }

  test('starts on the form stage', () {
    final controller = buildController();

    expect(controller.stage, AddCarWizardStage.form);
    expect(controller.carDraft, isNull);
    expect(controller.itemDrafts, isNull);
    expect(controller.errorText, isNull);
  });

  test('submitting car draft converts template into item drafts', () async {
    final controller = buildController();

    await controller.submitCarDraft(makeCar());

    expect(controller.stage, AddCarWizardStage.items);
    expect(controller.itemDrafts!.map((item) => item.name), [
      '机油',
      '汽油滤芯',
    ]);
    expect(controller.loadedTemplates, same(fuelTemplates));
    expect(
      controller.itemModelKey,
      (brand: '奥迪', model: '奥迪A3', powertrain: PowertrainType.fuel),
    );
  });

  test('stage is loading between submit and template resolve', () async {
    final completer = Completer<List<VehicleDefaultMaintenanceItem>>();
    final controller = buildController(loader: (_) => completer.future);

    final pending = controller.submitCarDraft(makeCar());
    expect(controller.stage, AddCarWizardStage.loading);

    completer.complete(fuelTemplates);
    await pending;
    expect(controller.stage, AddCarWizardStage.items);
  });

  test('same model key reuses edited drafts without reloading template', () async {
    var loadCount = 0;
    final controller = buildController(
      loader: (_) async {
        loadCount += 1;
        return fuelTemplates;
      },
    );
    await controller.submitCarDraft(makeCar());
    final edited = [makeDraft('手改项目')];
    controller.itemDrafts = edited;

    controller.returnToCarStep();
    expect(controller.stage, AddCarWizardStage.form);

    await controller.submitCarDraft(makeCar());

    expect(loadCount, 1);
    expect(controller.itemDrafts, same(edited));
    expect(controller.stage, AddCarWizardStage.items);
  });

  test('powertrain change reloads template into fresh drafts', () async {
    final controller = buildController(
      loader: (key) async =>
          key.powertrain == PowertrainType.fuel ? fuelTemplates : bevTemplates,
    );
    await controller.submitCarDraft(makeCar());

    controller.returnToCarStep();
    await controller.submitCarDraft(
      makeCar(powertrain: PowertrainType.electric),
    );

    expect(controller.stage, AddCarWizardStage.items);
    expect(controller.itemDrafts!.map((item) => item.name), ['减速器油']);
    expect(
      controller.itemModelKey,
      (brand: '奥迪', model: '奥迪A3', powertrain: PowertrainType.electric),
    );
  });

  test('template failure falls back to form stage with visible error',
      () async {
    final error = Exception('模板加载失败');
    final controller = buildController(loader: (_) async => throw error);

    await controller.submitCarDraft(makeCar());

    expect(controller.stage, AddCarWizardStage.form);
    expect(controller.carDraft, isNull);
    expect(controller.errorText, friendlyError(error));
  });

  test('next submit after failure clears the error', () async {
    var calls = 0;
    final controller = buildController(
      loader: (_) async {
        calls += 1;
        if (calls == 1) {
          throw Exception('模板加载失败');
        }
        return fuelTemplates;
      },
    );

    await controller.submitCarDraft(makeCar());
    expect(controller.errorText, isNotNull);

    await controller.submitCarDraft(makeCar());
    expect(controller.errorText, isNull);
    expect(controller.stage, AddCarWizardStage.items);
  });

  test('stale template result is dropped after car draft changed', () async {
    final completers =
        <PowertrainType, Completer<List<VehicleDefaultMaintenanceItem>>>{};
    final controller = buildController(
      loader: (key) => completers
          .putIfAbsent(
            key.powertrain,
            () => Completer<List<VehicleDefaultMaintenanceItem>>(),
          )
          .future,
    );

    final first = controller.submitCarDraft(makeCar());
    final second = controller.submitCarDraft(
      makeCar(powertrain: PowertrainType.electric),
    );

    // 第一个结果迟到：草稿已换车，过期结果要被丢弃（不能覆盖新键）。
    completers[PowertrainType.fuel]!.complete(fuelTemplates);
    await first;
    expect(controller.itemDrafts, isNull);
    expect(controller.itemModelKey, isNull);
    expect(controller.stage, AddCarWizardStage.loading);

    completers[PowertrainType.electric]!.complete(bevTemplates);
    await second;
    expect(controller.stage, AddCarWizardStage.items);
    expect(controller.itemDrafts!.map((item) => item.name), ['减速器油']);
  });

  test('stale template failure does not clobber the newer car draft',
      () async {
    final completers =
        <PowertrainType, Completer<List<VehicleDefaultMaintenanceItem>>>{};
    final controller = buildController(
      loader: (key) => completers
          .putIfAbsent(
            key.powertrain,
            () => Completer<List<VehicleDefaultMaintenanceItem>>(),
          )
          .future,
    );

    final first = controller.submitCarDraft(makeCar());
    final second = controller.submitCarDraft(
      makeCar(powertrain: PowertrainType.electric),
    );

    // 第一次加载失败迟到：已换草稿，旧失败不清状态、不报错误。
    completers[PowertrainType.fuel]!.completeError(Exception('模板加载失败'));
    await first;
    expect(controller.carDraft, isNotNull);
    expect(controller.carDraft!.powertrainType, PowertrainType.electric);
    expect(controller.errorText, isNull);
    expect(controller.stage, AddCarWizardStage.loading);

    completers[PowertrainType.electric]!.complete(bevTemplates);
    await second;
    expect(controller.stage, AddCarWizardStage.items);
  });

  test('submit validation requires at least one enabled item', () async {
    final controller = buildController();
    // 草稿未转出时不校验（widget 层有 null 守卫，不会走到提交）。
    expect(controller.validateForSubmit(), isNull);

    await controller.submitCarDraft(makeCar());
    controller.itemDrafts = [
      makeDraft('机油', enabled: false),
      makeDraft('汽油滤芯', enabled: false),
    ];
    expect(controller.validateForSubmit(), '至少保留一个可用保养项目');

    controller.itemDrafts = [
      makeDraft('机油', enabled: false),
      makeDraft('汽油滤芯'),
    ];
    expect(controller.validateForSubmit(), isNull);
  });

  test('restore defaults appends converted drafts', () async {
    final controller = buildController();
    await controller.submitCarDraft(makeCar());

    controller.restoreDefaults([makeTemplate('机油')]);

    expect(controller.itemDrafts, hasLength(3));
    expect(controller.itemDrafts!.last.name, '机油');
  });

  test('add draft appends to the draft list', () async {
    final controller = buildController();
    await controller.submitCarDraft(makeCar());

    controller.addDraft(makeDraft('自定义项目'));

    expect(controller.itemDrafts, hasLength(3));
    expect(controller.itemDrafts!.last.name, '自定义项目');
  });
}

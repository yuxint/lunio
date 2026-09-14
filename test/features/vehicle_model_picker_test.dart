// 车型选择器派生逻辑的单元测试（filterVehicleModels / deriveBrands /
// effectiveBrand）：空关键词全量、关键词对"品牌+车型"拼接做包含匹配、
// 关键词先去空白、品牌按出现顺序去重、选中品牌被滤掉时回退第一个。
//
// 这些派生此前内联在选择 sheet 的 build 里（还出过"build 里改字段"的
// 副作用 bug），抽纯函数后从接口直测；sheet 交互（渲染/自定义输入弹窗）
// 由 widget 测试覆盖。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/powertrain_type.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/entities/vehicle_model.dart';
import 'package:lunio/features/shell/profile/vehicle_model_picker.dart';

VehicleModel makeModel(String brand, String model, PowertrainType template) {
  return VehicleModel(
    brand: brand,
    model: model,
    template: template,
    sortOrder: 0,
    sync: SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026, 9, 1),
    ),
  );
}

void main() {
  final catalog = [
    makeModel('奥迪', '奥迪A3', PowertrainType.fuel),
    makeModel('日产', '轩逸', PowertrainType.fuel),
    makeModel('日产', '轩逸EV', PowertrainType.electric),
  ];

  test('empty keyword returns a copy of the full catalog', () {
    final filtered = filterVehicleModels(catalog, '');

    expect(filtered, hasLength(3));
    expect(filtered, isNot(same(catalog)));
    expect(filterVehicleModels(catalog, '   '), hasLength(3));
  });

  test('keyword matches brand+model concatenation', () {
    // "迪A" 单独不在品牌也不在车型里，拼起来（奥迪奥迪A3）才命中。
    expect(filterVehicleModels(catalog, '迪A').single.model, '奥迪A3');
    expect(filterVehicleModels(catalog, '轩逸').map((m) => m.model), [
      '轩逸',
      '轩逸EV',
    ]);
    expect(filterVehicleModels(catalog, '不存在'), isEmpty);
  });

  test('keyword is trimmed before matching', () {
    // 去空白后与" 轩逸"同样命中两条（含轩逸EV），证明空白被剥掉。
    expect(filterVehicleModels(catalog, ' 轩逸 ').map((m) => m.model), [
      '轩逸',
      '轩逸EV',
    ]);
  });

  test('brands derive in first-appearance order without duplicates', () {
    expect(deriveBrands(catalog), ['奥迪', '日产']);
    expect(deriveBrands(filterVehicleModels(catalog, '轩逸')), ['日产']);
    expect(deriveBrands(filterVehicleModels(catalog, '不存在')), isEmpty);
  });

  test('effective brand falls back to the first when filtered out', () {
    expect(effectiveBrand(['奥迪', '日产'], '日产'), '日产');
    // 搜索把选中品牌滤掉：回退第一个，只影响高亮不回写字段。
    expect(effectiveBrand(['日产'], '奥迪'), '日产');
    // 无匹配品牌时维持原选中值。
    expect(effectiveBrand([], '奥迪'), '奥迪');
  });
}

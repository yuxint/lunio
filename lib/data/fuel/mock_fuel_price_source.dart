// 示例油价数据源（FuelPriceSource 的内置假实现，见 docs/adr/0001）。
//
// 真接口定下来后：在本目录新增一个实现类（走 HTTP 拉真价），
// 再把 providers.dart 里 fuelPriceSourceProvider 换成新实现即可，
// 业务代码、页面、缓存逻辑都不用动。
//
// 示例价规则：全国基准价 + 按省份下标的固定小偏移，让不同省看到
// 不同的（但稳定可复现的）示例价。
import '../../domain/entities/fuel_price.dart';

class MockFuelPriceSource implements FuelPriceSource {
  const MockFuelPriceSource();

  /// 全国 31 个省级行政区（不含港澳台）。省份选择器的数据源，
  /// UI 层也从这里取，避免两处各维护一份省份清单。
  static const List<String> provinces = [
    '北京', '天津', '河北', '山西', '内蒙古', '辽宁', '吉林', '黑龙江',
    '上海', '江苏', '浙江', '安徽', '福建', '江西', '山东', '河南',
    '湖北', '湖南', '广东', '广西', '海南', '重庆', '四川', '贵州',
    '云南', '西藏', '陕西', '甘肃', '青海', '宁夏', '新疆',
  ];

  /// 产品确认的省份默认值。
  static const String defaultProvince = '湖北';

  /// 全国基准示例价（元/升）。
  static const Map<FuelGrade, double> _basePrices = {
    FuelGrade.gasoline92: 7.45,
    FuelGrade.gasoline95: 7.98,
    FuelGrade.gasoline98: 8.86,
    FuelGrade.diesel0: 7.12,
  };

  @override
  Future<FuelPriceData> fetchPrices(String province) async {
    // 示例源没有网络开销，稍作延迟模拟真实接口的节奏，
    // 避免页面状态切换快到看不出加载过程。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final offset = provinces.indexOf(province) * 0.01;
    return FuelPriceData(
      province: province,
      effectiveDate: null,
      fetchedAt: DateTime.now(),
      pricePerLiterByGrade: {
        for (final entry in _basePrices.entries)
          entry.key: double.parse((entry.value + offset).toStringAsFixed(2)),
      },
    );
  }
}

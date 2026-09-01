// 油品编号枚举：加油预测支持的油的种类。
//
// 纯 Dart 领域对象（不依赖 Flutter）。code 是稳定标识（存偏好/备份用它，
// 不要把展示文案当标识）；label 只用于界面显示。
enum FuelGrade {
  gasoline92('92', '92#'),
  gasoline95('95', '95#'),
  gasoline98('98', '98#'),
  diesel0('0', '0#');

  const FuelGrade(this.code, this.label);

  /// 稳定标识：偏好表与备份 JSON 里存这个（'92'/'95'/'98'/'0'）。
  final String code;

  /// 界面展示文案。
  final String label;

  /// 从存储 code 反序列化；未知 code 返回 null（调用方决定回退默认值）。
  static FuelGrade? tryParse(String code) {
    for (final grade in FuelGrade.values) {
      if (grade.code == code) {
        return grade;
      }
    }
    return null;
  }
}

/// 一次油价拉取的完整结果（≈ 我们自己的"油价字段契约"）。
///
/// 业务代码只认这里的字段，不认任何外部接口的返回结构——
/// 换外部接口只改 FuelPriceSource 适配器（见 docs/adr/0001）。
class FuelPriceData {
  const FuelPriceData({
    required this.province,
    required this.pricePerLiterByGrade,
    required this.fetchedAt,
    this.effectiveDate,
  });

  /// 从数据源 JSON 反序列化（当前只有偏好缓存这一个持久化场景）。
  factory FuelPriceData.fromJson(Map<String, Object?> json) {
    final prices = (json['prices'] as Map).cast<String, Object?>();
    return FuelPriceData(
      province: json['province'] as String,
      effectiveDate: json['effectiveDate'] as String?,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      pricePerLiterByGrade: {
        for (final entry in prices.entries)
          if (FuelGrade.tryParse(entry.key) != null)
            FuelGrade.tryParse(entry.key)!: (entry.value as num).toDouble(),
      },
    );
  }

  /// 省份名（与"省份油价"里的省一致，如'湖北'）。
  final String province;

  /// 各油品的每升单价（元）。数据源没给的油品不出现在 map 里。
  final Map<FuelGrade, double> pricePerLiterByGrade;

  /// 油价的生效日期（yyyy-MM-dd，数据源给什么存什么，可为 null）。
  final String? effectiveDate;

  /// 本地拉取成功的时间（判断"是否需要重新拉取"的依据）。
  final DateTime fetchedAt;

  /// 某油品的每升单价；该油品无价返回 null。
  double? priceFor(FuelGrade grade) => pricePerLiterByGrade[grade];

  /// 序列化为 JSON 存偏好表（油价缓存 key）。
  Map<String, Object?> toJson() {
    return {
      'province': province,
      'effectiveDate': effectiveDate,
      'fetchedAt': fetchedAt.toIso8601String(),
      'prices': {
        for (final entry in pricePerLiterByGrade.entries)
          entry.key.code: entry.value,
      },
    };
  }
}

/// 油价数据源契约（≈ Java 里手写的接口 + 适配器模式）。
///
/// 真接口定下来后：在 data 层新增一个实现类，替换 providers.dart 里
/// fuelPriceSourceProvider 的注入即可，业务代码与页面不动。
abstract interface class FuelPriceSource {
  /// 拉取某省全部油品的每升油价。网络失败抛异常，由调用方决定回退策略。
  Future<FuelPriceData> fetchPrices(String province);
}

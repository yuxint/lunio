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

/// 调价预告的趋势方向（涨/跌）。
///
/// 预告文字只会说"预计上调/下调"，JSON 里存 name（'up'/'down'），
/// 不要把中文展示文案当标识。
enum FuelPriceTrend {
  up('上调'),
  down('下调');

  const FuelPriceTrend(this.label);

  /// 界面展示文案。
  final String label;

  /// 从存储 name 反序列化；未知值返回 null（调用方按无预告处理）。
  static FuelPriceTrend? tryParse(String name) {
    for (final trend in FuelPriceTrend.values) {
      if (trend.name == name) {
        return trend;
      }
    }
    return null;
  }
}

/// 调价预告：数据源页面附带的"下次调价日期 + 预计每升涨/跌金额"。
///
/// 见 CONTEXT.md"调价预告"与 docs/adr/0006。日期只有月/日（预告原文
/// 不带年份，调价一定在近期，展示原样即可）；每升变动常是一个区间
/// （吨→升换算因油品密度不同），参与计算时取中值（见 FuelRules）。
class FuelAdjustmentForecast {
  const FuelAdjustmentForecast({
    required this.month,
    required this.day,
    required this.trend,
    required this.minChangePerLiter,
    required this.maxChangePerLiter,
  });

  /// 从数据源 JSON 反序列化（油价缓存 key 里的 forecast 字段）。
  /// 结构不完整/非法返回 null（宽松规则：预告缺失不算错误）。
  static FuelAdjustmentForecast? tryFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final month = json['month'];
    final day = json['day'];
    final trend = FuelPriceTrend.tryParse(json['trend'] as String? ?? '');
    final min = (json['minPerLiter'] as num?)?.toDouble();
    final max = (json['maxPerLiter'] as num?)?.toDouble();
    if (month is! int || day is! int || trend == null || min == null) {
      return null;
    }
    return FuelAdjustmentForecast(
      month: month,
      day: day,
      trend: trend,
      minChangePerLiter: min,
      maxChangePerLiter: max ?? min,
    );
  }

  /// 下次调价日期的月（1–12）。
  final int month;

  /// 下次调价日期的日（1–31）。
  final int day;

  /// 预计涨/跌方向。
  final FuelPriceTrend trend;

  /// 预计每升变动的下限（元/升，取绝对值；单值预告时与上限相等）。
  final double minChangePerLiter;

  /// 预计每升变动的上限（元/升，取绝对值；单值预告时与下限相等）。
  final double maxChangePerLiter;

  /// 预计每升变动的中值（元/升，取绝对值）。区间展示与计算都用它。
  double get midChangePerLiter =>
      (minChangePerLiter + maxChangePerLiter) / 2;

  /// 序列化进油价缓存 JSON。
  Map<String, Object?> toJson() => {
    'month': month,
    'day': day,
    'trend': trend.name,
    'minPerLiter': minChangePerLiter,
    'maxPerLiter': maxChangePerLiter,
  };
}

/// 一次油价拉取的完整结果（≈ 我们自己的"油价字段契约"）。
///
/// 数据源首页一次就返回全国 31 个省级行政区的价格（见 docs/adr/0006），
/// 所以这里存"省 → 油品 → 每升单价"的全国价表，换省不用重新拉取。
/// 业务代码只认这里的字段，不认任何外部接口的返回结构——
/// 换外部接口只改 FuelPriceSource 适配器（见 docs/adr/0001）。
class FuelPriceData {
  const FuelPriceData({
    required this.fetchedAt,
    required this.pricesByProvince,
    this.forecast,
  });

  /// 从数据源 JSON 反序列化（当前只有偏好缓存这一个持久化场景）。
  /// 结构不符合当前契约（如旧版单省缓存）直接抛异常，
  /// 由 Repository 按"缓存损坏"打日志并当无缓存处理。
  factory FuelPriceData.fromJson(Map<String, Object?> json) {
    final prices = (json['prices'] as Map).map((province, grades) {
      if (province is! String || grades is! Map) {
        throw FormatException('油价缓存 prices 结构非法');
      }
      return MapEntry<String, Map<FuelGrade, double>>(province, {
        for (final entry in grades.entries)
          if (entry.key is String &&
              FuelGrade.tryParse(entry.key as String) != null)
            FuelGrade.tryParse(entry.key as String)!:
                (entry.value as num).toDouble(),
      });
    });
    return FuelPriceData(
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      pricesByProvince: prices,
      forecast: FuelAdjustmentForecast.tryFromJson(json['forecast']),
    );
  }

  /// 本地拉取成功的时间（判断"是否需要重新拉取"的依据）。
  final DateTime fetchedAt;

  /// 全国价表：省名 → 油品 → 每升单价（元）。省份名与省份选择器一致。
  final Map<String, Map<FuelGrade, double>> pricesByProvince;

  /// 调价预告；数据源没给或解析不到时为 null（不算错误）。
  final FuelAdjustmentForecast? forecast;

  /// 某省某油品的每升单价；该省/该油品无价返回 null。
  double? priceFor({required String province, required FuelGrade grade}) {
    return pricesByProvince[province]?[grade];
  }

  /// 序列化为 JSON 存偏好表（油价缓存 key）。
  Map<String, Object?> toJson() {
    return {
      'fetchedAt': fetchedAt.toIso8601String(),
      'prices': {
        for (final entry in pricesByProvince.entries)
          entry.key: {
            for (final grade in entry.value.entries)
              grade.key.code: grade.value,
          },
      },
      if (forecast != null) 'forecast': forecast!.toJson(),
    };
  }
}

/// 油价数据源契约（≈ Java 里手写的接口 + 适配器模式）。
///
/// 真源是 qiyoujiage 网页（见 docs/adr/0006）；换源时在 data 层新增
/// 一个实现类，替换 providers.dart 里 fuelPriceSourceProvider 的注入
/// 即可，业务代码与页面不动。
abstract interface class FuelPriceSource {
  /// 拉取全国各省各油品的每升油价与调价预告。
  /// 网络失败/解析不到油价主体抛异常，由调用方决定回退策略。
  Future<FuelPriceData> fetchPrices();
}

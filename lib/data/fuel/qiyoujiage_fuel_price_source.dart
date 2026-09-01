// qiyoujiage 网页油价数据源（FuelPriceSource 的真实现，见 docs/adr/0006）。
//
// 数据来自 http://m.qiyoujiage.com 首页（无公开 JSON 接口）：
//  - 一张表格：全国 31 个省级行政区 × 4 个油品（92/95/98/0#）的每升价；
//  - 一段调价预告文字："下次油价9月11日24时调整,目前预计下调油价60元/吨
//    (0.05元/升-0.06元/升)..."。
//
// 解析用宽松规则：正则抽表格行/预告句式的关键内容，不依赖精确 DOM
// 层级，个别字段解析不到宁缺毋错（油价主体解析不到才抛异常）。
// 站点改版会解析失败 → 控制器保留旧缓存，页面显示错误态可手动重试。
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/fuel_price.dart';

class QiyouJiaFuelPriceSource implements FuelPriceSource {
  QiyouJiaFuelPriceSource({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// 数据源首页（明文 http，iOS 需 ATS 例外域，见 docs/adr/0006）。
  static final Uri homepage = Uri.http('m.qiyoujiage.com', '/');

  /// 全国 31 个省级行政区（不含港澳台）。省份选择器的数据源，
  /// UI 层也从这里取，避免两处各维护一份省份清单。
  /// 顺序与站点首页表格一致（表格解析按名字匹配，不按下标）。
  static const List<String> provinces = [
    '北京', '天津', '河北', '山西', '内蒙古', '辽宁', '吉林', '黑龙江',
    '上海', '江苏', '浙江', '安徽', '福建', '江西', '山东', '河南',
    '湖北', '湖南', '广东', '广西', '海南', '重庆', '四川', '贵州',
    '云南', '西藏', '陕西', '甘肃', '青海', '宁夏', '新疆',
  ];

  /// 产品确认的省份默认值。
  static const String defaultProvince = '湖北';

  @override
  Future<FuelPriceData> fetchPrices() async {
    final response = await _client.get(
      homepage,
      // 站点对无 UA 的请求可能返回简化页，带上移动端浏览器 UA。
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
      },
    );
    if (response.statusCode != 200) {
      throw FuelSourceException('油价页 HTTP ${response.statusCode}');
    }
    // 站点响应头 content-type 不带 charset，http 包会按 latin-1 解码，
    // 中文省份名会全变乱码；页面实际是 UTF-8（<meta charset> 有声明），
    // 这里对字节流显式按 UTF-8 解码（见 docs/adr/0006）。
    final body = utf8.decode(response.bodyBytes);
    return parseFuelPriceHtml(body, fetchedAt: DateTime.now());
  }
}

/// 油价数据源拉取/解析失败（HTTP 状态码非 200，或页面结构变化导致
/// 油价主体解析不到）。控制器捕获后退回旧缓存。
class FuelSourceException implements Exception {
  const FuelSourceException(this.message);

  final String message;

  @override
  String toString() => 'FuelSourceException: $message';
}

/// 表格行（宽松匹配，允许属性与嵌套）。
final RegExp _tableRowPattern = RegExp(
  r'<tr[^>]*>(.*?)</tr>',
  dotAll: true,
);

/// 表格单元格。
final RegExp _tableCellPattern = RegExp(
  r'<td[^>]*>(.*?)</td>',
  dotAll: true,
);

/// 任意标签（剥掉后剩纯文本）。
final RegExp _tagPattern = RegExp(r'<[^>]+>');

/// script 块（连同内容一起去掉：页面脚本里也有同款预告句，取正文那段）。
final RegExp _scriptPattern = RegExp(
  r'<script.*?</script>',
  dotAll: true,
);

/// 调价预告日期："下次油价9月11日24时调整"。
final RegExp _forecastDatePattern = RegExp(r'下次油价(\d{1,2})月(\d{1,2})日');

/// 预告句窗口字符数：日期命中点往后取这一段找方向与金额。站点预告
/// 句式固定为"下次油价X月X日24时调整,目前预计上调/下调油价N元/吨
/// (M元/升-P元/升)…"，方向与金额都在日期之后、同一句内，窗口远大于
/// 整句长度，足够覆盖。
const int _forecastSegmentChars = 120;

/// 预告句的结束标记（句号或换行标签）：窗口截到最近的标记为止，
/// 标记之后的内容（其他文章）不再参与解析。
const List<String> _forecastStopMarkers = ['。', '<br'];

/// 调价预告的每升变动额："0.05元/升"、"0.05元/升-0.06元/升"。
final RegExp _changePerLiterPattern = RegExp(r'(\d+(?:\.\d+)?)元/升');

/// 解析油价页 HTML 为 [FuelPriceData]（顶层函数，便于对真实页面 fixture
/// 直接做测试）。
///
/// 宽松规则：
///  - 逐 `<tr>` 抽 `<td>` 文本，首个单元格是已知省份名、后面 4 格能
///    解析出价格才算数（表头行"地区/92号汽油/…"自然被跳过）；
///  - 预告只在正文（去掉 script）里找日期，方向与金额限定在日期命中句
///    的窗口内，缺任何一样整体按"无预告"处理；
///  - 油价主体一格都解析不到时抛 [FuelSourceException]。
FuelPriceData parseFuelPriceHtml(
  String html, {
  required DateTime fetchedAt,
}) {
  final prices = <String, Map<FuelGrade, double>>{};
  // 站点表格列序固定为 92/95/98/0#。
  const gradeColumns = [
    FuelGrade.gasoline92,
    FuelGrade.gasoline95,
    FuelGrade.gasoline98,
    FuelGrade.diesel0,
  ];
  for (final rowMatch in _tableRowPattern.allMatches(html)) {
    final cells = _tableCellPattern
        .allMatches(rowMatch.group(1)!)
        .map((match) => _cellText(match.group(1)!))
        .toList();
    if (cells.length < gradeColumns.length + 1) {
      continue;
    }
    final province = cells[0];
    if (!QiyouJiaFuelPriceSource.provinces.contains(province)) {
      continue;
    }
    final provincePrices = <FuelGrade, double>{};
    for (var i = 0; i < gradeColumns.length; i++) {
      final value = double.tryParse(cells[i + 1]);
      if (value != null) {
        provincePrices[gradeColumns[i]] = value;
      }
    }
    if (provincePrices.isNotEmpty) {
      prices[province] = provincePrices;
    }
  }

  if (prices.isEmpty) {
    throw const FuelSourceException('油价表格解析不到任何省份价格');
  }

  return FuelPriceData(
    fetchedAt: fetchedAt,
    pricesByProvince: prices,
    forecast: _parseForecast(html),
  );
}

/// 解析调价预告；日期、方向、每升变动额缺任何一样都返回 null
/// （宽松规则：预告是附加信息，解析不到不影响油价主体）。
/// 方向与金额只在日期命中句的窗口内找：页面其他文章里也可能出现
/// "预计上调"或别的"X元/升"，全文搜索会把它们错算进预告。
FuelAdjustmentForecast? _parseForecast(String html) {
  final bodyText = html.replaceAll(_scriptPattern, '');
  final dateMatch = _forecastDatePattern.firstMatch(bodyText);
  if (dateMatch == null) {
    return null;
  }
  final segment = _forecastSentence(bodyText, dateMatch);
  // 方向字样按"预计上调/下调"找；两个都不在就当没预告。
  final FuelPriceTrend trend;
  if (segment.contains('预计上调')) {
    trend = FuelPriceTrend.up;
  } else if (segment.contains('预计下调')) {
    trend = FuelPriceTrend.down;
  } else {
    return null;
  }
  final amounts = _changePerLiterPattern
      .allMatches(segment)
      .map((match) => double.tryParse(match.group(1)!))
      .whereType<double>()
      .toList();
  if (amounts.isEmpty) {
    return null;
  }
  // 区间两个值取大小排好；单值预告下限=上限（中值即它本身）。
  var minChange = amounts.first;
  var maxChange = amounts.first;
  for (final amount in amounts.skip(1)) {
    if (amount < minChange) {
      minChange = amount;
    }
    if (amount > maxChange) {
      maxChange = amount;
    }
  }
  return FuelAdjustmentForecast(
    month: int.parse(dateMatch.group(1)!),
    day: int.parse(dateMatch.group(2)!),
    trend: trend,
    minChangePerLiter: minChange,
    maxChangePerLiter: maxChange,
  );
}

/// 从日期命中点开始截取预告句：往后取固定窗口，再在最近的结束标记
/// （句号/换行标签）处截断，防止同窗口内后续句子串进来。
/// 站点改了句式导致截断过头时，方向或金额找不到 → 整体按无预告处理。
String _forecastSentence(String bodyText, RegExpMatch dateMatch) {
  final start = dateMatch.start;
  final windowEnd =
      (dateMatch.end + _forecastSegmentChars).clamp(start, bodyText.length);
  var segment = bodyText.substring(start, windowEnd);
  for (final marker in _forecastStopMarkers) {
    final index = segment.indexOf(marker);
    if (index > 0) {
      segment = segment.substring(0, index);
    }
  }
  return segment;
}

/// 单元格文本：剥标签、去实体空格、去首尾空白
/// （省份格内含 <a> 链接，价格格可能有杂散空白）。
String _cellText(String raw) {
  return raw
      .replaceAll(_tagPattern, '')
      .replaceAll('&nbsp;', ' ')
      .trim();
}

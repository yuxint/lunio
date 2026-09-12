// qiyoujiage 网页油价数据源（FuelPriceSource 的真实现，见 docs/adr/0006
// 与 docs/adr/0011）。
//
// 数据来自 http://m.qiyoujiage.com 的**省份详情页**（如 /hubei.shtml，
// 无公开 JSON 接口）：
//  - 一个价格块：<dt>湖北92号汽油</dt><dd>8.31(元)</dd> × 4 个油品
//    （92/95/98/0#），页面标题下带站点自己的更新日期戳；
//  - 一段调价预告文字："下次油价9月11日24时调整,目前预计上调油价260
//    元/吨(0.20元/升-0.24元/升)..."。
//
// 为什么抓详情页而不是首页全国表格：站点首页的表格和预告在调价落地后
// 会滞后多天不更新（2026-09-12 实测：9-11 24时调价后首页湖北仍是旧价
// 8.10、预告还挂在"9月11日调整"，而各省详情页当天就已更新），详情页
// 才是站点的第一手更新点，所以按当前省份逐页抓取（ADR 0011）。
//
// 解析用宽松规则：正则抽价格块/预告句式的关键内容，不依赖精确 DOM
// 层级，个别字段解析不到宁缺毋错（油价主体解析不到才抛异常）。
// 站点改版会解析失败 → 控制器保留旧缓存，页面显示错误态可手动重试。
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/fuel_price.dart';

class QiyouJiaFuelPriceSource implements FuelPriceSource {
  QiyouJiaFuelPriceSource({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// 数据源域名（明文 http，iOS 需 ATS 例外域，见 docs/adr/0006）。
  static const String _host = 'm.qiyoujiage.com';

  /// 省份名 → 详情页路径段（/hubei.shtml 的 hubei）。清单与站点首页
  /// 栏目导航一致（2026-09-12 核对）；山西/陕西同音，站点用 shanxi（山西）
  /// 与 shanxi-3（陕西）区分。
  static const Map<String, String> provincePaths = {
    '北京': 'beijing',
    '天津': 'tianjin',
    '河北': 'hebei',
    '山西': 'shanxi',
    '内蒙古': 'neimenggu',
    '辽宁': 'liaoning',
    '吉林': 'jilin',
    '黑龙江': 'heilongjiang',
    '上海': 'shanghai',
    '江苏': 'jiangsu',
    '浙江': 'zhejiang',
    '安徽': 'anhui',
    '福建': 'fujian',
    '江西': 'jiangxi',
    '山东': 'shandong',
    '河南': 'henan',
    '湖北': 'hubei',
    '湖南': 'hunan',
    '广东': 'guangdong',
    '广西': 'guangxi',
    '海南': 'hainan',
    '重庆': 'chongqing',
    '四川': 'sichuan',
    '贵州': 'guizhou',
    '云南': 'yunnan',
    '西藏': 'xizang',
    '陕西': 'shanxi-3',
    '甘肃': 'gansu',
    '青海': 'qinghai',
    '宁夏': 'ningxia',
    '新疆': 'xinjiang',
  };

  /// 全国 31 个省级行政区（不含港澳台）。省份选择器的数据源，
  /// UI 层也从这里取，避免两处各维护一份省份清单。
  static List<String> get provinces => provincePaths.keys.toList();

  /// 产品确认的省份默认值。
  static const String defaultProvince = '湖北';

  /// 某省详情页的地址。
  static Uri provincePageUri(String province) =>
      Uri.http(_host, '/${provincePaths[province]}.shtml');

  @override
  Future<FuelPriceData> fetchPrices({required String province}) async {
    final path = provincePaths[province];
    if (path == null) {
      throw FuelSourceException('未知省份：$province');
    }
    final response = await _client.get(
      provincePageUri(province),
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
    return parseFuelProvinceHtml(
      body,
      province: province,
      fetchedAt: DateTime.now(),
    );
  }
}

/// 油价数据源拉取/解析失败（HTTP 状态码非 200、未知省份，或页面结构
/// 变化导致油价主体解析不到）。控制器捕获后退回旧缓存。
class FuelSourceException implements Exception {
  const FuelSourceException(this.message);

  final String message;

  @override
  String toString() => 'FuelSourceException: $message';
}

/// 价格块（宽松匹配，允许属性与 dt/dd 之间有空白）：
/// `<dt>湖北92号汽油</dt><dd>8.31(元)</dd>`。
final RegExp _priceItemPattern = RegExp(
  r'<dt[^>]*>(.*?)</dt>\s*<dd[^>]*>(.*?)</dd>',
  dotAll: true,
);

/// 任意标签（剥掉后剩纯文本）。
final RegExp _tagPattern = RegExp(r'<[^>]+>');

/// script 块（连同内容一起去掉：页面脚本里也有同款预告句，取正文那段）。
final RegExp _scriptPattern = RegExp(
  r'<script.*?</script>',
  dotAll: true,
);

/// 价格块 dt 文本 → 油品：站点以"92号汽油/95号汽油/98号汽油/0号柴油"
/// 命名（dt 全文是"省名+油品"，省份归属另在解析入口校验）。
const Map<String, FuelGrade> _gradeKeywords = {
  '92号汽油': FuelGrade.gasoline92,
  '95号汽油': FuelGrade.gasoline95,
  '98号汽油': FuelGrade.gasoline98,
  '0号柴油': FuelGrade.diesel0,
};

/// 价格数值："8.31(元)" 里的数字部分。
final RegExp _priceNumberPattern = RegExp(r'\d+(?:\.\d+)?');

/// 调价预告日期："下次油价9月11日24时调整"。
final RegExp _forecastDatePattern = RegExp(r'下次油价(\d{1,2})月(\d{1,2})日');

/// 预告句窗口字符数：日期命中点往后取这一段找方向与金额。站点预告
/// 句式固定为"下次油价X月X日24时调整(,)?目前预计上调/下调油价N元/吨
/// (M元/升-P元/升)…"，方向与金额都在日期之后、同一句内，窗口远大于
/// 整句长度，足够覆盖。
const int _forecastSegmentChars = 120;

/// 预告句的结束标记（句号）：窗口截到最近的标记为止，标记之后的内容
/// （其他文章）不再参与解析。（标签已先行剥掉，不再需要 <br> 标记。）
const List<String> _forecastStopMarkers = ['。'];

/// 调价预告的每升变动额："0.05元/升"、"0.05元/升-0.06元/升"。
final RegExp _changePerLiterPattern = RegExp(r'(\d+(?:\.\d+)?)元/升');

/// 解析省份详情页 HTML 为 [FuelPriceData]（顶层函数，便于对真实页面
/// fixture 直接做测试）。
///
/// 宽松规则：
///  - 逐 `<dt>/<dd>` 对抽价格：dt 文本须含目标省名（防串页/改版误收）
///    且命中已知油品关键词，dd 抽第一个数字当每升价；解析不到的油品
///    宁缺毋错；
///  - 预告只在正文（去掉 script、剥掉标签）里找日期，方向与金额限定在
///    日期命中句的窗口内，缺任何一样整体按"无预告"处理；
///  - 油价主体一格都解析不到时抛 [FuelSourceException]。
FuelPriceData parseFuelProvinceHtml(
  String html, {
  required String province,
  required DateTime fetchedAt,
}) {
  final pricesByGrade = <FuelGrade, double>{};
  for (final match in _priceItemPattern.allMatches(html)) {
    final label = _plainText(match.group(1)!);
    if (!label.contains(province)) {
      continue;
    }
    final grade = _gradeForLabel(label);
    if (grade == null) {
      continue;
    }
    final value = _priceNumberPattern
        .firstMatch(_plainText(match.group(2)!))
        ?.group(0);
    final price = double.tryParse(value ?? '');
    if (price != null) {
      pricesByGrade[grade] = price;
    }
  }

  if (pricesByGrade.isEmpty) {
    throw FuelSourceException('油价页解析不到 $province 的任何价格');
  }

  return FuelPriceData(
    province: province,
    fetchedAt: fetchedAt,
    pricesByGrade: pricesByGrade,
    forecast: _parseForecast(html),
  );
}

/// 从价格块 dt 文本匹配油品；不含任何已知油品关键词返回 null。
FuelGrade? _gradeForLabel(String label) {
  for (final entry in _gradeKeywords.entries) {
    if (label.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

/// 解析调价预告；日期、方向、每升变动额缺任何一样都返回 null
/// （宽松规则：预告是附加信息，解析不到不影响油价主体）。
/// 方向与金额只在日期命中句的窗口内找：页面其他文章里也可能出现
/// "预计上调"或别的"X元/升"，全文搜索会把它们错算进预告。
FuelAdjustmentForecast? _parseForecast(String html) {
  // 先去掉 script（脚本里有同款预告句），再剥掉所有标签：详情页的
  // 预告日期包在 <span> 里、日期后紧跟 <br> 才接方向金额，带着标签
  // 截句会把方向/金额截掉；剥标签后日期与方向自然连成一句。
  final bodyText = html
      .replaceAll(_scriptPattern, '')
      .replaceAll(_tagPattern, '');
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
/// （句号）处截断，防止同窗口内后续句子串进来。
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

/// 标签内文本：先剥内嵌标签，再去实体空格、去首尾空白。dt/dd 内容
/// 可能带内嵌标签（如加粗油品名），不剥的话标签属性里的数字会被价格
/// 正则抢先命中算错价（宁缺毋错）。
String _plainText(String raw) {
  return raw
      .replaceAll(_tagPattern, '')
      .replaceAll('&nbsp;', ' ')
      .trim();
}

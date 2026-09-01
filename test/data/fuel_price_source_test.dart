// qiyoujiage 油价源解析测试：用真实页面截取的表格与调价预告原文做
// fixture，守住宽松解析规则（表格逐行抽省份、预告句式抽日期/方向/区间）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/data/fuel/qiyoujiage_fuel_price_source.dart';
import 'package:lunio/domain/entities/fuel_price.dart';

/// 真实首页（2026-09-01 抓取）截取的两行 + 表头行 + 一段脚本里的
/// 同款预告句（验证脚本内容不参与预告解析）。
const fixtureHtml = '''
<html><head>
<script>var tishiContent="下次油价9月11日24时调整<br/>目前预计上调油价99元/吨(0.99元/升),";</script>
</head><body>
<div class="rdglBox">
<table border="1" id="youtable"><tbody>
<tr><td>地区</td><td>92号汽油</td><td>95号汽油</td><td>98号汽油</td><td>0号柴油</td></tr>
<tr><td><a href="/beijing.shtml" title="北京油价">北京</a></td><td>8.09</td><td>8.61</td><td>10.11</td><td>7.81</td></tr>
<tr><td><a href="/hubei.shtml" title="湖北油价">湖北</a></td><td>8.10</td><td>8.67</td><td>9.99</td><td>7.75</td></tr>
</tbody></table>
</div>
<div style=" border:solid 1px #009cff;">
下次油价9月11日24时调整,目前预计下调油价60元/吨(0.05元/升-0.06元/升),大家相互转告油价或下跌。<br/>
</div>
</body></html>
''';

void main() {
  final fetchedAt = DateTime(2026, 9, 1, 10);

  group('parseFuelPriceHtml 表格解析', () {
    test('逐行抽省份价格，省份格含链接也能剥干净', () {
      final data = parseFuelPriceHtml(fixtureHtml, fetchedAt: fetchedAt);
      expect(data.pricesByProvince.keys, ['北京', '湖北']);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline92), 8.10);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline95), 8.67);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline98), 9.99);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.diesel0), 7.75);
      expect(data.priceFor(province: '北京', grade: FuelGrade.gasoline92), 8.09);
      // 表头行（地区/92号汽油/…）不会变成一个假省份。
      expect(data.pricesByProvince.containsKey('地区'), isFalse);
    });

    test('省份名不在已知清单里的行跳过（宽松规则防误收）', () {
      const html = '<table><tr><td>深圳</td><td>8.10</td><td>8.78</td>'
          '<td>10.78</td><td>7.76</td></tr></table>';
      expect(
        () => parseFuelPriceHtml(html, fetchedAt: fetchedAt),
        throwsA(isA<FuelSourceException>()),
      );
    });

    test('整页解析不到价格时抛 FuelSourceException', () {
      expect(
        () => parseFuelPriceHtml('<html>页面改版了</html>', fetchedAt: fetchedAt),
        throwsA(
          isA<FuelSourceException>().having(
            (error) => error.message,
            'message',
            contains('解析不到'),
          ),
        ),
      );
    });

    test('个别价格格脏了不影响同省其他油品（宁缺毋错）', () {
      const html = '<table><tr><td>湖北</td><td>8.10</td><td>--</td>'
          '<td>9.99</td><td>7.75</td></tr></table>';
      final data = parseFuelPriceHtml(html, fetchedAt: fetchedAt);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline95), isNull);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline98), 9.99);
    });
  });

  group('parseFuelPriceHtml 调价预告解析', () {
    test('日期/方向/区间从正文解析，脚本里的同款句被剔除', () {
      final data = parseFuelPriceHtml(fixtureHtml, fetchedAt: fetchedAt);
      final forecast = data.forecast;
      expect(forecast, isNotNull);
      // 正文是"下调 0.05~0.06"；脚本里那句"上调 0.99"必须不影响结果。
      expect(forecast!.trend, FuelPriceTrend.down);
      expect(forecast.month, 9);
      expect(forecast.day, 11);
      expect(forecast.minChangePerLiter, 0.05);
      expect(forecast.maxChangePerLiter, 0.06);
      expect(forecast.midChangePerLiter, closeTo(0.055, 1e-9));
    });

    test('单值预告（只有一个 元/升）下限=上限', () {
      const html = '<div>下次油价9月11日24时调整,目前预计下调油价60元/吨'
          '(0.05元/升),大家相互转告。</div>'
          '<table><tr><td>湖北</td><td>8.10</td><td>8.67</td><td>9.99</td>'
          '<td>7.75</td></tr></table>';
      final forecast = parseFuelPriceHtml(html, fetchedAt: fetchedAt).forecast!;
      expect(forecast.minChangePerLiter, 0.05);
      expect(forecast.maxChangePerLiter, 0.05);
      expect(forecast.midChangePerLiter, 0.05);
    });

    test('正文其他文章里的同款字样不影响日期命中句的预告解析', () {
      // 预告句之后的其他文章含"预计上调"（方向判断里上调优先）和更大的
      // "0.99元/升"：不锚定到命中句的话，方向会被带成上调、区间上限被带成 0.99。
      const html = '<div>下次油价9月11日24时调整,目前预计下调油价60元/吨'
          '(0.05元/升-0.06元/升),大家相互转告油价或下跌。<br/></div>'
          '<div>上一轮调价窗口：预计上调油价50元/吨(0.04元/升-0.99元/升)。'
          '今日92号汽油平均价格为8.10元/升。</div>'
          '<table><tr><td>湖北</td><td>8.10</td><td>8.67</td><td>9.99</td>'
          '<td>7.75</td></tr></table>';
      final forecast = parseFuelPriceHtml(html, fetchedAt: fetchedAt).forecast!;
      expect(forecast.trend, FuelPriceTrend.down);
      expect(forecast.minChangePerLiter, 0.05);
      expect(forecast.maxChangePerLiter, 0.06);
      expect(forecast.midChangePerLiter, closeTo(0.055, 1e-9));
    });

    test('缺日期/缺方向/缺每升变动额都整体按无预告处理', () {
      final noDate =
          '<div>预计下调油价60元/吨(0.05元/升-0.06元/升)。</div>'
          '<table><tr><td>湖北</td><td>8.10</td><td>8.67</td><td>9.99</td>'
          '<td>7.75</td></tr></table>';
      final noTrend =
          '<div>下次油价9月11日24时调整,油价60元/吨(0.05元/升)。</div>'
          '<table><tr><td>湖北</td><td>8.10</td><td>8.67</td><td>9.99</td>'
          '<td>7.75</td></tr></table>';
      final noAmount =
          '<div>下次油价9月11日24时调整,目前预计下调油价60元/吨。</div>'
          '<table><tr><td>湖北</td><td>8.10</td><td>8.67</td><td>9.99</td>'
          '<td>7.75</td></tr></table>';
      expect(parseFuelPriceHtml(noDate, fetchedAt: fetchedAt).forecast, isNull);
      expect(parseFuelPriceHtml(noTrend, fetchedAt: fetchedAt).forecast, isNull);
      expect(parseFuelPriceHtml(noAmount, fetchedAt: fetchedAt).forecast, isNull);
    });
  });

  group('FuelPriceData JSON 往返（缓存契约）', () {
    test('解析结果 toJson → fromJson 字段一致', () {
      final data = parseFuelPriceHtml(fixtureHtml, fetchedAt: fetchedAt);
      final restored = FuelPriceData.fromJson(
        data.toJson(),
      );
      expect(restored.fetchedAt, data.fetchedAt);
      expect(
        restored.priceFor(province: '湖北', grade: FuelGrade.gasoline92),
        8.10,
      );
      expect(restored.forecast?.trend, FuelPriceTrend.down);
      expect(restored.forecast?.midChangePerLiter, closeTo(0.055, 1e-9));
    });
  });
}

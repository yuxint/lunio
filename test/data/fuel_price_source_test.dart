// qiyoujiage 油价源解析测试：用真实省份详情页（2026-09-12 抓取的
// /hubei.shtml）截取的价格块与调价预告原文做 fixture，守住宽松解析
// 规则（dt/dd 抽省价、预告句式抽日期/方向/区间）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/data/fuel/qiyoujiage_fuel_price_source.dart';
import 'package:lunio/domain/entities/fuel_price.dart';

/// 真实湖北详情页（2026-09-12 抓取）截取的价格块与预告段。注意两个
/// 结构事实：预告日期包在 <span> 里、日期后紧跟 <br/> 才接方向金额
/// （剥标签前截句会把方向/金额截掉）；页面 script 里有同款预告句
/// （内容不参与解析）。
const fixtureHtml = '''
<html><head>
<script>var tishiContent="下次油价9月11日24时调整<br/>目前预计上调油价260元/吨(0.20元/升-0.24元/升),";</script>
</head><body>
<div id="content" class="daota01">
  <div class="daota01_title">
    <h1>湖北油价</h1>
    2026-09-12 </div>
  <div class="table_wrap">
    <div class="content_youjia">
      <dl>
        <dt>湖北92号汽油</dt>
        <dd>8.31(元)</dd>
      </dl>
      <dl>
        <dt>湖北95号汽油</dt>
        <dd>8.89(元)</dd>
      </dl>
      <dl>
        <dt>湖北98号汽油</dt>
        <dd>10.29(元)</dd>
      </dl>
      <dl>
        <dt>湖北0号柴油</dt>
        <dd>7.96(元)</dd>
      </dl>
    </div>
    <div class="tishi"> <span>下次油价9月11日24时调整</span><br/>
目前预计上调油价260元/吨(0.20元/升-0.24元/升),大家相互转告油价又涨了。<br/>
<script>
var wxname="youjiagogo";
</script>
</div>
  </div>
</div>
</body></html>
''';

void main() {
  final fetchedAt = DateTime(2026, 9, 12, 10);

  group('parseFuelProvinceHtml 价格块解析', () {
    test('逐块抽省份价格，四个油品齐全且归属省份正确', () {
      final data = parseFuelProvinceHtml(
        fixtureHtml,
        province: '湖北',
        fetchedAt: fetchedAt,
      );
      expect(data.province, '湖北');
      expect(data.pricesByGrade.length, 4);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline92), 8.31);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline95), 8.89);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline98), 10.29);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.diesel0), 7.96);
    });

    test('dt 不含目标省名的价格块跳过（防串页/改版误收）', () {
      const html = '<dl><dt>陕西92号汽油</dt><dd>8.17(元)</dd></dl>'
          '<dl><dt>湖北95号汽油</dt><dd>8.89(元)</dd></dl>';
      final data = parseFuelProvinceHtml(
        html,
        province: '湖北',
        fetchedAt: fetchedAt,
      );
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline92), isNull);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline95), 8.89);
    });

    test('dt 不含已知油品关键词的块跳过', () {
      const html = '<dl><dt>湖北92号汽油</dt><dd>8.31(元)</dd></dl>'
          '<dl><dt>湖北油价走势</dt><dd>8.31(元)</dd></dl>';
      final data = parseFuelProvinceHtml(
        html,
        province: '湖北',
        fetchedAt: fetchedAt,
      );
      expect(data.pricesByGrade.length, 1);
    });

    test('价格格脏了不影响同省其他油品（宁缺毋错）', () {
      const html = '<dl><dt>湖北92号汽油</dt><dd>--(元)</dd></dl>'
          '<dl><dt>湖北98号汽油</dt><dd>10.29(元)</dd></dl>';
      final data = parseFuelProvinceHtml(
        html,
        province: '湖北',
        fetchedAt: fetchedAt,
      );
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline92), isNull);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline98), 10.29);
    });

    test('dt/dd 内嵌标签剥掉后再取关键词与价格（属性数字不算价格）', () {
      // dt 里油品关键词被标签拆开（剥标签后才连续）；dd 里数字前面的
      // 标签属性带数字（不剥标签会被价格正则抢先命中算成 9.0）。
      const html = '<dl><dt>湖北<b>92号</b>汽油</dt><dd>8.31(元)</dd></dl>'
          '<dl><dt>湖北95号汽油</dt><dd><i class="n9">8.89</i>(元)</dd></dl>';
      final data = parseFuelProvinceHtml(
        html,
        province: '湖北',
        fetchedAt: fetchedAt,
      );
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline92), 8.31);
      expect(data.priceFor(province: '湖北', grade: FuelGrade.gasoline95), 8.89);
    });

    test('整页解析不到价格时抛 FuelSourceException', () {
      expect(
        () => parseFuelProvinceHtml(
          '<html>页面改版了</html>',
          province: '湖北',
          fetchedAt: fetchedAt,
        ),
        throwsA(
          isA<FuelSourceException>().having(
            (error) => error.message,
            'message',
            contains('解析不到'),
          ),
        ),
      );
    });
  });

  group('parseFuelProvinceHtml 调价预告解析', () {
    test('日期在 span 里、<br/> 后接方向金额也能解析（详情页句式）', () {
      final data = parseFuelProvinceHtml(
        fixtureHtml,
        province: '湖北',
        fetchedAt: fetchedAt,
      );
      final forecast = data.forecast;
      expect(forecast, isNotNull);
      expect(forecast!.trend, FuelPriceTrend.up);
      expect(forecast.month, 9);
      expect(forecast.day, 11);
      expect(forecast.minChangePerLiter, 0.20);
      expect(forecast.maxChangePerLiter, 0.24);
      expect(forecast.midChangePerLiter, closeTo(0.22, 1e-9));
    });

    test('script 里的同款预告句被剔除，不参与解析', () {
      // 正文预告是上调 0.20~0.24；head script 里那句写个大相径庭的
      // "下调 0.99"：不剔除的话方向与区间都会被带歪。
      const html = '<html><head>'
          '<script>var tishiContent="下次油价9月11日24时调整<br/>'
          '目前预计下调油价99元/吨(0.99元/升),";</script>'
          '</head><body>'
          '<div class="tishi"> <span>下次油价9月11日24时调整</span><br/>'
          '目前预计上调油价260元/吨(0.20元/升-0.24元/升),大家相互转告。</div>'
          '<dl><dt>湖北92号汽油</dt><dd>8.31(元)</dd></dl>'
          '</body></html>';
      final forecast = parseFuelProvinceHtml(
        html,
        province: '湖北',
        fetchedAt: fetchedAt,
      ).forecast!;
      expect(forecast.trend, FuelPriceTrend.up);
      expect(forecast.minChangePerLiter, 0.20);
      expect(forecast.maxChangePerLiter, 0.24);
    });

    test('单值预告（只有一个 元/升）下限=上限', () {
      const html = '<div class="tishi"> <span>下次油价9月11日24时调整</span><br/>'
          '目前预计下调油价60元/吨(0.05元/升),大家相互转告。</div>'
          '<dl><dt>湖北92号汽油</dt><dd>8.31(元)</dd></dl>';
      final forecast = parseFuelProvinceHtml(
        html,
        province: '湖北',
        fetchedAt: fetchedAt,
      ).forecast!;
      expect(forecast.minChangePerLiter, 0.05);
      expect(forecast.maxChangePerLiter, 0.05);
      expect(forecast.midChangePerLiter, 0.05);
    });

    test('预告句号截断：其他文章里的同款字样不影响解析', () {
      // 预告句之后的其他文章含"预计下调"（与正文方向相反）和更大的
      // "0.99元/升"：不按句号截断的话，区间上限会被带成 0.99。
      const html = '<div class="tishi"> <span>下次油价9月11日24时调整</span><br/>'
          '目前预计上调油价260元/吨(0.20元/升-0.24元/升),大家相互转告。</div>'
          '<div>上一轮调价窗口：预计下调油价50元/吨(0.04元/升-0.99元/升)。</div>'
          '<dl><dt>湖北92号汽油</dt><dd>8.31(元)</dd></dl>';
      final forecast = parseFuelProvinceHtml(
        html,
        province: '湖北',
        fetchedAt: fetchedAt,
      ).forecast!;
      expect(forecast.trend, FuelPriceTrend.up);
      expect(forecast.minChangePerLiter, 0.20);
      expect(forecast.maxChangePerLiter, 0.24);
    });

    test('缺日期/缺方向/缺每升变动额都整体按无预告处理', () {
      final noDate =
          '<div>目前预计下调油价60元/吨(0.05元/升-0.06元/升)。</div>'
          '<dl><dt>湖北92号汽油</dt><dd>8.31(元)</dd></dl>';
      final noTrend =
          '<div><span>下次油价9月11日24时调整</span><br/>'
          '油价60元/吨(0.05元/升)。</div>'
          '<dl><dt>湖北92号汽油</dt><dd>8.31(元)</dd></dl>';
      final noAmount =
          '<div><span>下次油价9月11日24时调整</span><br/>'
          '目前预计下调油价60元/吨。</div>'
          '<dl><dt>湖北92号汽油</dt><dd>8.31(元)</dd></dl>';
      FuelPriceData parse(String html) => parseFuelProvinceHtml(
            html,
            province: '湖北',
            fetchedAt: fetchedAt,
          );
      expect(parse(noDate).forecast, isNull);
      expect(parse(noTrend).forecast, isNull);
      expect(parse(noAmount).forecast, isNull);
    });
  });

  group('省份清单与地址', () {
    test('31 个省级行政区都有详情页路径，默认值在清单里', () {
      expect(QiyouJiaFuelPriceSource.provinces.length, 31);
      for (final province in QiyouJiaFuelPriceSource.provinces) {
        expect(
          QiyouJiaFuelPriceSource.provincePaths[province],
          isNotNull,
          reason: '$province 缺详情页路径',
        );
      }
      expect(
        QiyouJiaFuelPriceSource.provinces,
        contains(QiyouJiaFuelPriceSource.defaultProvince),
      );
    });

    test('同音省份的路径区分山西/陕西', () {
      expect(QiyouJiaFuelPriceSource.provincePaths['山西'], 'shanxi');
      expect(QiyouJiaFuelPriceSource.provincePaths['陕西'], 'shanxi-3');
      expect(
        QiyouJiaFuelPriceSource.provincePageUri('湖北').toString(),
        'http://m.qiyoujiage.com/hubei.shtml',
      );
    });

    test('未知省份在发请求前就抛 FuelSourceException', () {
      final source = QiyouJiaFuelPriceSource();
      expect(
        () => source.fetchPrices(province: '火星'),
        throwsA(isA<FuelSourceException>()),
      );
    });
  });

  group('FuelPriceData JSON 往返（缓存契约）', () {
    test('解析结果 toJson → fromJson 字段一致', () {
      final data = parseFuelProvinceHtml(
        fixtureHtml,
        province: '湖北',
        fetchedAt: fetchedAt,
      );
      final restored = FuelPriceData.fromJson(data.toJson());
      expect(restored.province, '湖北');
      expect(restored.fetchedAt, data.fetchedAt);
      expect(
        restored.priceFor(province: '湖北', grade: FuelGrade.gasoline92),
        8.31,
      );
      expect(restored.forecast?.trend, FuelPriceTrend.up);
      expect(restored.forecast?.midChangePerLiter, closeTo(0.22, 1e-9));
    });

    test('省份不匹配时 priceFor 返回 null（换省后旧缓存不透出）', () {
      final data = parseFuelProvinceHtml(
        fixtureHtml,
        province: '湖北',
        fetchedAt: fetchedAt,
      );
      expect(
        data.priceFor(province: '广东', grade: FuelGrade.gasoline92),
        isNull,
      );
    });

    test('旧版全国价表缓存 JSON 结构不符合契约，抛异常按无缓存处理', () {
      // 旧结构：顶层没有 province，prices 是"省 → 油品"两级。
      const nationalJson = '''
      {"fetchedAt":"2026-08-31T00:00:00.000","prices":{"湖北":{"92":7.45}}}
      ''';
      expect(
        () => FuelPriceData.fromJson(
          (const JsonDecoder().convert(nationalJson) as Map)
              .cast<String, Object?>(),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

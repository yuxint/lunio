// 油价域的状态接缝（fuel_page 的数据后端）。
//
// 职责：油价域全部 provider 的定义与派生——省份/油品/手填价三个全局
// 偏好、油价数据源注入点、油价控制器（缓存优先 → 新鲜期判断 → 换省
// 守卫 → 自动拉取 → 失败退旧缓存，手动刷新走 manualRefresh），以及
// 生效链派生：生效价（手填优先 → 数据源当前省当前油品价）、生效预告
// （过滤过期后的调价预告）、预估价（生效价 + 预告变动中值）。
// 语义依据见 CONTEXT.md"加油预测"与 docs/adr/0011。
//
// 在 App 中的位置：fuel_page 消费本文件的全部 provider（价格卡、
// 档位列表、预估块）；app_shell 在加油开关打开时 watch 油价控制器
// 做启动静默预取。保存动作（换省/油品/手填价写库后的失效）仍在
// shell_actions.dart；备份恢复/清空数据经 providers.dart 的偏好失效
// 名单逐出本文件，因此本文件与 providers.dart 互相 import（Dart 循环
// import 合法；两边各自只取所需，保持这个环最小）。
//
// （Java 类比：一个域的 @Configuration + 派生 Bean 集中在域自己的
// 装配文件里，全局配置类只保留失效名单对它们的引用。）

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/fuel/qiyoujiage_fuel_price_source.dart';
import '../../../domain/entities/fuel_price.dart';
import '../../../domain/rules/fuel_rules.dart';

/// 加油预测的省份（全局一份，默认湖北，产品确认）。
final fuelProvinceProvider = FutureProvider<String>((ref) async {
  return await ref.watch(lunioPreferencesProvider).getFuelProvince() ??
      QiyouJiaFuelPriceSource.defaultProvince;
});

/// 加油预测的油品编号（全局一份，单选，默认 92#；解析与默认值在门面）。
final fuelGradeProvider = FutureProvider<FuelGrade>((ref) {
  return ref.watch(lunioPreferencesProvider).getFuelGrade();
});

/// 油价数据源（≈ Java 里注入接口实现的地方）。真源是 qiyoujiage 网页
/// 解析（见 docs/adr/0006）；换源时在这里换成新实现即可。
final fuelPriceSourceProvider = Provider<FuelPriceSource>(
  (ref) => QiyouJiaFuelPriceSource(),
);

/// 当前"省+油品"的手填价（用户手填的每升价，优先于数据源价格）。
/// 无手填返回 null。写入口在动作层 saveFuelManualPrice（手填/重置）。
final fuelManualPriceProvider = FutureProvider<double?>((ref) async {
  final province = await ref.watch(fuelProvinceProvider.future);
  final grade = await ref.watch(fuelGradeProvider.future);
  return ref
      .watch(fuelRepositoryProvider)
      .getFuelManualPrice(province: province, grade: grade);
});

/// 油价状态控制器：缓存优先，过期/无缓存时自动拉取，
/// 失败退回旧缓存。手动刷新走 [FuelPriceController.manualRefresh]。
///
/// watch 时机：AppShell（加油开关开着时，≈ 启动检查）与加油页。
/// 缓存是单省价表（当前省份 + 调价预告，见 docs/adr/0011），所以这里
/// watch 省份偏好：换省后缓存省份不匹配，按"暂无数据"处理、等用户点
/// "刷新"再拉新省（用户决策 2026-09-12，不自动发请求）。
final fuelPriceControllerProvider =
    AsyncNotifierProvider<FuelPriceController, FuelPriceData?>(
      FuelPriceController.new,
    );

class FuelPriceController extends AsyncNotifier<FuelPriceData?> {
  @override
  Future<FuelPriceData?> build() async {
    final fuelRepository = ref.watch(fuelRepositoryProvider);
    final province = await ref.watch(fuelProvinceProvider.future);
    final cache = await fuelRepository.getFuelPriceCache();
    final fresh = !FuelRules.shouldRefreshFuelPrices(
      lastFetchedAt: cache?.fetchedAt,
      now: DateTime.now(),
    );
    if (cache != null && cache.province == province && fresh) {
      return cache;
    }
    // 换省后缓存归属对不上：直接展示空态（价格里的省份守卫也拦住旧省
    // 价透出），不自动拉取——由用户点"刷新"显式拉新省价格。
    if (cache != null && cache.province != province) {
      return null;
    }
    try {
      final data = await ref
          .watch(fuelPriceSourceProvider)
          .fetchPrices(province: province);
      await fuelRepository.saveFuelPriceCache(data);
      return data;
    } catch (error) {
      // 拉取失败退回旧缓存（可能为 null → 页面显示"暂无油价数据"）。
      // 缓存损坏已被 FuelRepository 按 null 处理，这里不会把坏数据透出。
      return cache;
    }
  }

  /// 手动刷新：无视新鲜期按当前省份强制拉一次。成功覆盖缓存与状态返回
  /// true；失败保留原状态数据（不覆盖，与"手填价不被覆盖"同语义，
  /// 价格里的省份守卫会拦住换省后残留的旧省缓存）返回 false。
  Future<bool> manualRefresh() async {
    final province = await ref.read(fuelProvinceProvider.future);
    state = const AsyncLoading<FuelPriceData?>();
    try {
      final data = await ref
          .read(fuelPriceSourceProvider)
          .fetchPrices(province: province);
      await ref
          .read(fuelRepositoryProvider)
          .saveFuelPriceCache(data);
      state = AsyncData(data);
      return true;
    } catch (error) {
      final previous = await ref
          .read(fuelRepositoryProvider)
          .getFuelPriceCache();
      state = AsyncData(previous);
      return false;
    }
  }
}

/// 当前生效的每升价（手填优先，其次数据源价）；都没有为 null。
/// 档位金额随价联动，抽成 provider 让列表只在价格变化时重算。
final effectiveFuelPriceProvider = Provider<double?>((ref) {
  final manualPrice = ref.watch(fuelManualPriceProvider).value;
  if (manualPrice != null) {
    return manualPrice;
  }
  final grade = ref.watch(fuelGradeProvider).value;
  final data = ref.watch(fuelPriceControllerProvider).value;
  if (grade == null) {
    return null;
  }
  final province = ref.watch(fuelProvinceProvider).value;
  if (province == null) {
    return null;
  }
  return data?.priceFor(province: province, grade: grade);
});

/// 生效中的调价预告（ADR 0011 修订）：过期预告按无预告处理——调价日
/// 早于当前应用日期即过期（规则与定年见 FuelRules.isForecastExpired）。
/// 缓存与控制器状态保真（仍存站点原话），过滤只在这一处做，预估块与
/// "调价后价格"列统一从这里取。
final effectiveFuelForecastProvider = Provider<FuelAdjustmentForecast?>((ref) {
  final forecast = ref.watch(fuelPriceControllerProvider).value?.forecast;
  if (forecast == null) {
    return null;
  }
  // "今天"未加载完成的瞬间按无预告处理（宁缺毋错，与源解析同口径）。
  final today = ref.watch(effectiveTodayProvider).value;
  if (today == null) {
    return null;
  }
  return FuelRules.isForecastExpired(forecast: forecast, today: today)
      ? null
      : forecast;
});

/// 预估调价后每升价（生效价 + 调价预告变动中值，见 docs/adr/0006）。
/// 无预告（含过期）/无生效价时为 null（"调价后价格"列显示占位符）。
final predictedFuelPriceProvider = Provider<double?>((ref) {
  final base = ref.watch(effectiveFuelPriceProvider);
  final forecast = ref.watch(effectiveFuelForecastProvider);
  if (base == null || forecast == null) {
    return null;
  }
  return FuelRules.predictedPricePerLiter(
    currentPricePerLiter: base,
    forecast: forecast,
  );
});

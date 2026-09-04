// Riverpod Provider 总入口（相当于 Spring 的 JavaConfig 配置类：
// 这里集中声明所有"Bean"，并定义它们之间的依赖关系）。
//
// ## 核心概念（Java 对照）
// - Provider        ≈ 单例 Bean，创建一次全局复用。
// - FutureProvider  ≈ @Async + 缓存的 Bean：首次被 watch 时执行异步方法，
//                    结果缓存；ref.invalidate(...) 相当于"逐出缓存"，
//                    下次 watch 会重新执行并刷新所有订阅它的 UI。
// - ref.watch(x)    ≈ 注入依赖 x 并订阅变化：x 变了，当前 provider 重算。
// - ref.read(x)     ≈ 注入依赖 x 但只取一次（常用于事件回调里），
//                    不会在 x 变化时触发任何刷新。
//
// ## 本 App 的状态管理约定（重要）
// Repository 的写方法（增删改）**不会**主动刷新任何缓存。写库后的缓存
// 逐出由"写库 → 失效 → 通知收尾"的编排统一收在保存动作层
// shell_actions.dart（每个业务变更一个具名函数，见 docs/adr/0007）；
// invalidateVehicleProviders / invalidatePreferenceProviders 降级为动作层
// 与少数既有调用方（备份恢复、清空数据、通知协调器）的内部实现。
// 这是"手动失效"模式：漏调 invalidate 会导致跨页面数据陈旧——因此
// 新增保存路径时进动作层加函数，不要在 UI 里手排失效序列。
//
// ## 依赖关系图
// ```text
// appDatabaseProvider（惰性建库/连库）
//   ├─ lunioPreferencesProvider（偏好 typed 门面）
//   ├─ builtInCatalogRepositoryProvider（车型目录/默认模板 + bootstrap）
//   ├─ fuelRepositoryProvider（加油域）
//   │    └─ backupRepositoryProvider（备份导出/恢复/清空，复用偏好门面）
//   ├─ lunioRepositoryProvider（主仓库：车辆/项目/记录，组合偏好门面与加油仓库）
//   │    ├─ developerModeProvider ──> manualDatePreferenceProvider
//   │    ├─ themeModePreferenceProvider（主题）
//   │    ├─ notificationSettingsProvider（3 个通知偏好一条 IN 查询）
//   │    ├─ parkingCountdownProvider（停车倒计时，存偏好表）
//   │    ├─ effectiveTodayProvider（手动日期 ?? 系统今天）
//   │    ├─ carsProvider ──> appliedCarProvider
//   │    │                    ├─ appliedCarMaintenanceItemsProvider
//   │    │                    └─ appliedCarRecordsProvider
//   │    └─ defaultMaintenanceBootstrapProvider（首启灌入车型库/默认项目）
//   │         └─ vehicleModelsProvider
//   └─ 加油域 provider（开关/省份/油品/手填价/油价控制器）挂 fuelRepositoryProvider
// ```
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date/app_date_context.dart';
import '../core/notifications/lunio_notification_service.dart';
import '../core/date/local_date.dart';
import '../data/database/app_database.dart';
import '../data/fuel/qiyoujiage_fuel_price_source.dart';
import '../data/preferences/app_preferences.dart';
import '../data/repositories/backup_repository.dart';
import '../data/repositories/built_in_catalog_repository.dart';
import '../data/repositories/fuel_repository.dart';
import '../data/repositories/lunio_repository.dart';
import '../domain/entities/car.dart';
import '../domain/entities/fuel_prediction.dart';
import '../domain/entities/fuel_price.dart';
import '../domain/entities/maintenance_item.dart';
import '../domain/entities/maintenance_record.dart';
import '../domain/entities/notification_settings.dart';
import '../domain/entities/parking_countdown.dart';
import '../domain/entities/vehicle_model.dart';
import '../domain/rules/fuel_rules.dart';

/// 应用日期上下文：目前只用它读"系统真实当前时间"（停车倒计时用）。
/// 手动日期（开发者模式）不会写进这里，而是走 [manualDatePreferenceProvider]，
/// 两者在 [effectiveTodayProvider] 处汇合，形成"业务日期/真实时间"双轨。
final appDateContextProvider = Provider<AppDateContext>(
  (ref) => AppDateContext.system(),
);

/// 开发者模式开关。入口在"我的"页版本号连点 5 次（profile_page.dart），
/// 控制手动日期行是否显示。
final developerModeProvider = FutureProvider<bool>((ref) async {
  return ref.watch(lunioPreferencesProvider).getDeveloperModeEnabled();
});

/// 手动覆盖日期（开发者模式专属）。三层条件全满足才生效：
/// 开发者模式开 → 手动日期开关开 → manualDate 偏好存在且可解析。
/// 任何一层不满足返回 null（即使用系统真实日期）。
final manualDatePreferenceProvider = FutureProvider<LocalDate?>((ref) async {
  final developerModeEnabled = await ref.watch(developerModeProvider.future);
  if (!developerModeEnabled) {
    return null;
  }
  final preferences = ref.watch(lunioPreferencesProvider);
  if (!await preferences.isManualDateEnabled()) {
    return null;
  }
  return preferences.getManualDate();
});

/// 主题模式偏好：'light' / 'dark' / 其他（含 null）都按 system 处理。
/// 被 LunioApp.watch，写入后经 invalidatePreferenceProviders 刷新。
final themeModePreferenceProvider = FutureProvider<ThemeMode>((ref) {
  return ref.watch(lunioPreferencesProvider).getThemeMode();
});

/// 通知设置：3 个偏好 key 一条 IN 查询（R27），取值约定与默认值在
/// 偏好门面里。保养到期提醒是产品核心能力，设计上不提供关闭入口
/// （R5，原 maintenanceDueEnabled 偏好已移除）。
final notificationSettingsProvider = FutureProvider<LunioNotificationSettings>((
  ref,
) {
  return ref.watch(lunioPreferencesProvider).readNotificationSettings();
});

/// 停车倒计时：临时状态，以 JSON 存在偏好表 `parkingCountdown` key 下，
/// 不进入 JSON 备份（备份契约见 backup_codec.dart）。
final parkingCountdownProvider = FutureProvider<ParkingCountdown?>((ref) {
  return ref.watch(lunioPreferencesProvider).getParkingCountdown();
});

// ---------------- 加油预测 ----------------

/// 加油预测功能开关。只在开发者模式里提供开关入口（入口见
/// profile_page.dart）；开发者模式关闭时入口会顺手清掉该偏好，所以
/// 这里不用叠加判断。被 AppShell watch：开关变化 → 底部"加油"tab
/// 实时出现/消失。
final fuelPredictionEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(lunioPreferencesProvider).getFuelPredictionEnabled();
});

/// 加油预测的省份（全局一份，默认湖北，产品确认）。
final fuelProvinceProvider = FutureProvider<String>((ref) async {
  return await ref.watch(lunioPreferencesProvider).getFuelProvince() ??
      QiyouJiaFuelPriceSource.defaultProvince;
});

/// 加油预测的油品编号（全局一份，单选，默认 92#；解析与默认值在门面）。
final fuelGradeProvider = FutureProvider<FuelGrade>((ref) {
  return ref.watch(lunioPreferencesProvider).getFuelGrade();
});

/// 当前应用车辆的加油预测设置（剩余油量 = 加满预估基准档，按车一条；
/// 油箱容积在 Car 上）。无应用车辆返回 null；
/// 从没保存过也是 null（页面按默认 50% 展示）。
final appliedCarFuelPredictionProvider =
    FutureProvider<FuelPrediction?>((ref) async {
      final car = await ref.watch(appliedCarProvider.future);
      if (car?.id == null) {
        return null;
      }
      return ref
          .watch(fuelRepositoryProvider)
          .getFuelPredictionForCar(car!.id!);
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
/// 缓存是全国价表（一次拉取含 31 省 + 调价预告，见 docs/adr/0006），
/// 所以不再 watch 省份偏好——换省直接读缓存里的价格，不重新拉取。
final fuelPriceControllerProvider =
    AsyncNotifierProvider<FuelPriceController, FuelPriceData?>(
      FuelPriceController.new,
    );

class FuelPriceController extends AsyncNotifier<FuelPriceData?> {
  @override
  Future<FuelPriceData?> build() async {
    final fuelRepository = ref.watch(fuelRepositoryProvider);
    final cache = await fuelRepository.getFuelPriceCache();
    final fresh = !FuelRules.shouldRefreshFuelPrices(
      lastFetchedAt: cache?.fetchedAt,
      now: DateTime.now(),
    );
    if (cache != null && fresh) {
      return cache;
    }
    try {
      final data = await ref.watch(fuelPriceSourceProvider).fetchPrices();
      await fuelRepository.saveFuelPriceCache(data);
      return data;
    } catch (error) {
      // 拉取失败退回旧缓存（可能为 null → 页面显示"暂无油价数据"）。
      // 缓存损坏已被 FuelRepository 按 null 处理，这里不会把坏数据透出。
      return cache;
    }
  }

  /// 手动刷新：无视新鲜期强制拉一次。成功覆盖缓存与状态返回 true；
  /// 失败保留原状态数据（不覆盖，与"手填价不被覆盖"同语义）返回 false。
  Future<bool> manualRefresh() async {
    state = const AsyncLoading<FuelPriceData?>();
    try {
      final data = await ref.read(fuelPriceSourceProvider).fetchPrices();
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

/// 全局生效的"今天"：手动日期优先，否则系统今天。
/// 所有业务日期口径（提醒进度、记录表单默认日期、snooze/ack 判断）都用它，
/// 只有停车倒计时和系统通知调度时刻用真实时间（tz.TZDateTime.now）。
final effectiveTodayProvider = FutureProvider<LocalDate>((ref) async {
  final baseDateContext = ref.watch(appDateContextProvider);
  final manualDate = await ref.watch(manualDatePreferenceProvider.future);
  return manualDate ?? baseDateContext.today();
});

/// 数据库 Provider。惰性创建：首个使用方 watch 时才 new AppDatabase()，
/// 而真正的 SQLite 连接由 Drift 的 LazyDatabase 推迟到第一条 SQL 才建立
/// （见 app_database.dart）。ref.onDispose ≈ 容器销毁时的 @PreDestroy 回调。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

/// 偏好门面：app_preferences 表的唯一读写出口（key/编解码/默认值都在
/// 模块内，调用方只见 typed 方法）。
final lunioPreferencesProvider = Provider<LunioPreferences>((ref) {
  return LunioPreferences(ref.watch(appDatabaseProvider));
});

/// 车型目录仓库：车型目录与默认模板两张内置表 + 首启 bootstrap 对账。
final builtInCatalogRepositoryProvider = Provider<BuiltInCatalogRepository>((
  ref,
) {
  return BuiltInCatalogRepository(ref.watch(appDatabaseProvider));
});

/// 加油仓库：加油预测设置、油价缓存、手填油价。
final fuelRepositoryProvider = Provider<FuelRepository>((ref) {
  return FuelRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(lunioPreferencesProvider),
  );
});

/// 备份仓库：备份导出、恢复、清空数据（数据生命周期域）。
final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(lunioPreferencesProvider),
  );
});

/// 主仓库：车辆/保养项目/保养记录核心域（组合偏好门面与加油仓库，
/// 删车级联时借道加油仓库删预测行）。
final lunioRepositoryProvider = Provider<LunioRepository>((ref) {
  return LunioRepository(
    ref.watch(appDatabaseProvider),
    preferences: ref.watch(lunioPreferencesProvider),
    fuel: ref.watch(fuelRepositoryProvider),
  );
});

/// 首启/升级引导：把 asset 里的内置车型目录与默认保养项目模板
/// 同步进数据库（幂等，按 catalogId upsert）。AppShell 首帧 watch 触发。
final defaultMaintenanceBootstrapProvider = FutureProvider<void>((ref) {
  return ref
      .watch(builtInCatalogRepositoryProvider)
      .ensureBootstrapData();
});

/// 车型库（约 190 个车型），供添加车辆向导的品牌/车型选择器使用。
/// 注意这里显式 await bootstrap 完成，保证车型目录已入库。
final vehicleModelsProvider = FutureProvider<List<VehicleModel>>((ref) async {
  await ref.watch(defaultMaintenanceBootstrapProvider.future);
  return ref.watch(builtInCatalogRepositoryProvider).listVehicleModels();
});

/// 当前用户所有车辆列表。显式 await bootstrap 完成（依赖显式化，R29）：
/// bootstrap 只写车型目录/默认模板两张内置表、不写 cars 表，
/// 行为与原先"只借用失效信号"等价，但依赖关系在代码里一目了然。
final carsProvider = FutureProvider<List<Car>>((ref) async {
  await ref.watch(defaultMaintenanceBootstrapProvider.future);
  return ref.watch(lunioRepositoryProvider).listCars();
});

/// 当前"应用车辆"（正在被提醒页/记录页展示的车）。
/// 显式 await carsProvider（依赖显式化，R29）；实际取值走
/// repository.getAppliedCar()，其内部按 AppliedCarRules 回退：
/// 偏好里的 appliedCarId 存在且有效则用它，否则回退第一辆车，无车返回 null。
final appliedCarProvider = FutureProvider<Car?>((ref) async {
  await ref.watch(carsProvider.future);
  return ref.watch(lunioRepositoryProvider).getAppliedCar();
});

/// 应用车辆的保养项目列表（含启用/停用状态）。无应用车辆时空列表。
final appliedCarMaintenanceItemsProvider =
    FutureProvider<List<MaintenanceItem>>((ref) async {
      final car = await ref.watch(appliedCarProvider.future);
      if (car?.id == null) {
        return const [];
      }
      return ref
          .watch(lunioRepositoryProvider)
          .listMaintenanceItemsForCar(car!.id!);
    });

/// 应用车辆的保养记录全量列表（记录页与提醒计算共用，无分页）。
final appliedCarRecordsProvider = FutureProvider<List<MaintenanceRecord>>((
  ref,
) async {
  final car = await ref.watch(appliedCarProvider.future);
  if (car?.id == null) {
    return const [];
  }
  return ref
      .watch(lunioRepositoryProvider)
      .listMaintenanceRecordsForCar(car!.id!);
});

/// 通知服务：生产装配为全局单例；测试可整体覆盖为新实例
/// （服务是普通可实例化类，实例间不共享状态）。
final lunioNotificationServiceProvider = Provider<LunioNotificationService>((
  ref,
) {
  return LunioNotificationService.instance;
});

/// 通知同步代数（≈ 乐观锁的版本号）：恢复备份/清空数据时 bump()，
/// 通知同步控制器（notification_sync_controller.dart）在途任务执行前
/// 比对快照代数，不一致即放弃——用于作废"用旧数据排通知"的竞态。
/// parking_countdown 的保存链路同样用它防错排。用 provider 而非全局
/// 变量，保证所有读取方走同一容器（R8）。
final notificationSyncGenerationProvider =
    NotifierProvider<NotificationSyncGeneration, int>(
      NotificationSyncGeneration.new,
    );

/// 代数 Notifier：state 从 0 起，bump() 自增。
class NotificationSyncGeneration extends Notifier<int> {
  @override
  int build() => 0;

  /// 代数 +1（作废全部在途通知同步任务）。
  void bump() => state = state + 1;
}

/// 车辆/项目/记录相关缓存整体失效（写库后由 UI 调用）。
/// 逐出的顺序无关紧要，Riverpod 会在下一帧统一重算被 watch 的 provider。
void invalidateVehicleProviders(WidgetRef ref) {
  ref.invalidate(carsProvider);
  ref.invalidate(vehicleModelsProvider);
  ref.invalidate(appliedCarProvider);
  ref.invalidate(appliedCarMaintenanceItemsProvider);
  ref.invalidate(appliedCarRecordsProvider);
}

/// 偏好类缓存整体失效的共用实现。WidgetRef 和容器 Ref 是两个没有共同
/// 父类的类型（riverpod 3.2 也未导出二者共同的参数类型 ProviderOrFamily），
/// 故用 dynamic 承接二者同签名的 invalidate；对外只暴露下面两个静态
/// 类型入口，调用侧不失去类型检查。
void _invalidatePreferences(dynamic ref) {
  ref.invalidate(developerModeProvider);
  ref.invalidate(manualDatePreferenceProvider);
  ref.invalidate(effectiveTodayProvider);
  ref.invalidate(themeModePreferenceProvider);
  ref.invalidate(notificationSettingsProvider);
  ref.invalidate(fuelPredictionEnabledProvider);
  ref.invalidate(fuelProvinceProvider);
  ref.invalidate(fuelGradeProvider);
  ref.invalidate(appliedCarFuelPredictionProvider);
  ref.invalidate(fuelManualPriceProvider);
  ref.invalidate(fuelPriceControllerProvider);
}

/// 偏好类缓存整体失效：开发者模式、手动日期、生效日期、主题、通知设置、
/// 加油预测（写库后由 UI 调用）。
void invalidatePreferenceProviders(WidgetRef ref) =>
    _invalidatePreferences(ref);

/// 偏好类缓存整体失效（provider 容器 Ref 版本）：通知协调器在写偏好后
/// 调用。
void invalidatePreferenceProvidersWithRef(Ref ref) =>
    _invalidatePreferences(ref);

/// 加油预测相关缓存失效：功能开关、省份、油品、当前车设置、
/// 手填价、油价控制器（换省/清缓存后整体重算）。
void invalidateFuelPreferenceProviders(WidgetRef ref) {
  ref.invalidate(fuelPredictionEnabledProvider);
  ref.invalidate(fuelProvinceProvider);
  ref.invalidate(fuelGradeProvider);
  ref.invalidate(appliedCarFuelPredictionProvider);
  ref.invalidate(fuelManualPriceProvider);
  ref.invalidate(fuelPriceControllerProvider);
}

/// 全量失效：恢复备份 / 清空数据后调用，让所有 FutureProvider 重新查库。
/// parkingCountdown 单独逐出（它不在上面两个方法里）。
void invalidateAllAppDataProviders(WidgetRef ref) {
  ref.invalidate(defaultMaintenanceBootstrapProvider);
  ref.invalidate(parkingCountdownProvider);
  invalidateVehicleProviders(ref);
  invalidatePreferenceProviders(ref);
}

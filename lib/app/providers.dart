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
// 逐出由"写库 → bump 数据纪元 → 通知收尾"的编排统一收在保存动作层
// shell_actions.dart（每个业务变更一个具名函数，见 docs/adr/0007）。
// 缓存逐出走两个"数据纪元"（与通知同步代数同构的版本号模型）：
// - 偏好纪元（preferencesEpochProvider，ADR 0017）：偏好表数据的
//   版本号，偏好写点 bump；
// - 车辆数据纪元（vehicleDataEpochProvider，ADR 0017 修订节）：车辆/
//   项目/记录/加油四张业务表数据的版本号，动作层写库函数 bump——
//   2026-10-06 起取代手工失效名单 invalidateVehicleProviders。
// 读对应表的 provider 在自己 build 首行 watch 纪元，纪元一变自动重查，
// 无名单可漏；新增保存路径进动作层加函数，不要在 UI 里手排失效序列。
//
// ## 依赖关系图
// ```text
// appDatabaseProvider（惰性建库/连库）
//   ├─ lunioPreferencesProvider（偏好 typed 门面）
//   ├─ builtInCatalogRepositoryProvider（车型目录/默认模板 + bootstrap）
//   ├─ fuelRepositoryProvider（加油域，另挂偏好门面）
//   ├─ backupRepositoryProvider（备份导出/恢复/清空，另挂偏好门面）
//   ├─ lunioRepositoryProvider（主仓库：车辆/项目/记录，组合偏好门面与加油仓库）
//   │    ├─ developerModeProvider ──> manualDatePreferenceProvider
//   │    ├─ themeModePreferenceProvider（主题）
//   │    ├─ notificationSettingsProvider（3 个通知偏好一条 IN 查询）
//   │    ├─ parkingCountdownProvider（停车倒计时，存偏好表）
//   │    ├─ effectiveTodayProvider（手动日期 ?? 系统今天）
//   │    ├─ carsProvider ──> appliedCarProvider
//   │    │                    ├─ appliedCarMaintenanceItemsProvider（派生自下面的 family）
//   │    │                    ├─ appliedCarRecordsProvider（派生自下面的 family）
//   │    │                    └─ appliedCarFuelRecordsProvider
//   │    │                       （派生自 fuelRecordsForCarProvider）
//   │    ├─ appliedCarBoardProvider（应用车辆数据束：上面四路的车/项目/
//   │    │    记录/生效今天一次拿齐，按车消费的页面与控制器共用的读侧接缝）
//   │    │    └─ costStatsDataProvider（费用统计页数据接缝：数据束 +
//   │    │       appliedCarFuelRecordsProvider 一次拿齐，页面单门卫）
//   │    ├─ maintenanceItemsForCarProvider（按车项目列表 family：项目 sheet / 记录表单行内新增）
//   │    ├─ recordsForCarProvider（按车记录 family：费用统计页等按车消费者）
//   │    └─ defaultMaintenanceBootstrapProvider（首启灌入车型库/默认项目）
//   │         └─ vehicleModelsProvider
//   ├─ defaultItemsTemplateProvider（向导默认模板 family，挂 builtInCatalogRepository）
//   └─ 加油域 provider：开关/当前车设置/加油记录（family + applied 派生）
//      在本文件；省份/油品/手填价/数据源/油价控制器/生效链在
//      features/shell/fuel/fuel_prices.dart
// ```
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date/app_date_context.dart';
import '../core/notifications/lunio_notification_service.dart';
import '../core/date/local_date.dart';
import '../core/platform/native_live_activities.dart';
import '../core/platform/native_widgets.dart';
import '../data/database/app_database.dart';
import '../data/preferences/app_preferences.dart';
import '../data/repositories/backup_repository.dart';
import '../data/repositories/built_in_catalog_repository.dart';
import '../data/repositories/fuel_repository.dart';
import '../data/repositories/lunio_repository.dart';
import '../domain/entities/car.dart';
import '../domain/entities/fuel_prediction.dart';
import '../domain/entities/fuel_record.dart';
import '../domain/entities/maintenance_item.dart';
import '../domain/entities/maintenance_record.dart';
import '../domain/entities/notification_settings.dart';
import '../domain/entities/parking_countdown.dart';
import '../domain/entities/powertrain_type.dart';
import '../domain/entities/vehicle_default_maintenance_item.dart';
import '../domain/entities/vehicle_model.dart';

/// 偏好纪元：偏好表数据的版本号，与通知同步代数（notification_sync_guard）
/// 同构（≈ Java 缓存失效用的版本戳）。任何偏好写入点写完库后 bump 一次；
/// 读偏好表的 provider 在 build 里 watch 本 provider，纪元一变自动重算。
/// 2026-09-26 起取代手工失效名单（原 _invalidatePreferences 家族已删除，
/// ADR 0017）：新增偏好派生 provider 时在 build 首行加
/// ref.watch(preferencesEpochProvider)，漏加只会让该 provider 自己陈旧，
/// 不再殃及名单其他成员。parkingCountdownProvider 不走纪元——它的写点
/// 直接逐出自己（"写点失效自己"模型，见动作层停车分节）。
final preferencesEpochProvider = NotifierProvider<PreferencesEpoch, int>(
  PreferencesEpoch.new,
);

/// 偏好纪元 Notifier：state 从 0 起，bump() 自增（写点在动作层偏好/加油
/// 分节与通知协调器）。
class PreferencesEpoch extends Notifier<int> {
  @override
  int build() => 0;

  /// 纪元 +1（作废全部偏好派生 provider 的缓存值）。
  void bump() => state = state + 1;
}

/// 车辆数据纪元：车辆/保养项目/保养记录/加油记录四张业务表数据的
/// 版本号，与偏好纪元（[preferencesEpochProvider]）同构（ADR 0017
/// 2026-10-06 修订节）。任何写这四张表的点写完库后 bump 一次；读这些
/// 表的 provider（cars、appliedCar、三个按车 family 及其 applied 派生、
/// vehicleModels）在 build 首行 watch 本 provider，纪元一变自动重算。
/// 2026-10-06 起取代手工失效名单（原 invalidateVehicleProviders 已
/// 删除）：新增按车派生缓存时在 build 首行加
/// ref.watch(vehicleDataEpochProvider)，漏加只会让该 provider 自己
/// 陈旧，不再殃及名单其他成员。不 watch 纪元的三个边界：
/// - defaultMaintenanceBootstrapProvider：做的是目录对账（幂等重灌），
///   恢复备份/清空数据后的重灌由 invalidateAllAppDataProviders 显式
///   失效触发——只 bump 车辆纪元不会重灌目录（vehicleModelsProvider
///   重查时 bootstrap 幂等 no-op）；
/// - parkingCountdownProvider：读偏好表，"写点直失效自己"模型（见
///   偏好纪元注释），车辆写库不牵动停车卡；
/// - appliedCarFuelPredictionProvider：读加油预测设置表，其真实写点
///   （档位落库）保留精准单点失效（ADR 0017 决定 5 边界）。
final vehicleDataEpochProvider = NotifierProvider<VehicleDataEpoch, int>(
  VehicleDataEpoch.new,
);

/// 车辆数据纪元 Notifier：state 从 0 起，bump() 自增（写点在动作层
/// 车辆/记录/项目/加油分节的保存函数与全量失效入口）。
class VehicleDataEpoch extends Notifier<int> {
  @override
  int build() => 0;

  /// 纪元 +1（作废全部车辆数据派生 provider 的缓存值）。
  void bump() => state = state + 1;
}

/// 应用日期上下文：目前只用它读"系统真实当前时间"（停车倒计时用）。
/// 手动日期（开发者模式）不会写进这里，而是走 [manualDatePreferenceProvider]，
/// 两者在 [effectiveTodayProvider] 处汇合，形成"业务日期/真实时间"双轨。
final appDateContextProvider = Provider<AppDateContext>(
  (ref) => AppDateContext.system(),
);

/// 开发者模式开关。入口在"我的"页版本号连点 5 次（profile_page.dart），
/// 控制手动日期行是否显示。
final developerModeProvider = FutureProvider<bool>((ref) async {
  ref.watch(preferencesEpochProvider);
  return ref.watch(lunioPreferencesProvider).getDeveloperModeEnabled();
});

/// 手动覆盖日期（开发者模式专属）。三层条件全满足才生效：
/// 开发者模式开 → 手动日期开关开 → manualDate 偏好存在且可解析。
/// 任何一层不满足返回 null（即使用系统真实日期）。
final manualDatePreferenceProvider = FutureProvider<LocalDate?>((ref) async {
  ref.watch(preferencesEpochProvider);
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
/// 被 LunioApp.watch，偏好写入点 bump 纪元后自动重算。
final themeModePreferenceProvider = FutureProvider<ThemeMode>((ref) {
  ref.watch(preferencesEpochProvider);
  return ref.watch(lunioPreferencesProvider).getThemeMode();
});

/// 通知设置：3 个偏好 key 一条 IN 查询（R27），取值约定与默认值在
/// 偏好门面里。保养到期提醒是产品核心能力，设计上不提供关闭入口
/// （R5，原 maintenanceDueEnabled 偏好已移除）。
final notificationSettingsProvider = FutureProvider<LunioNotificationSettings>((
  ref,
) {
  ref.watch(preferencesEpochProvider);
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
  ref.watch(preferencesEpochProvider);
  return ref.watch(lunioPreferencesProvider).getFuelPredictionEnabled();
});

/// 当前应用车辆的加油预测设置（剩余油量 = 加满预估基准档，按车一条；
/// 油箱容积在 Car 上）。无应用车辆返回 null；
/// 从没保存过也是 null（页面按默认 50% 展示）。
/// 失效随偏好纪元走（2026-09-26 收编时保持旧名单集合、边界不动，
/// ADR 0017）；它的真实写点（档位落库）另做精准单点失效（saveFuelBaseline）。
final appliedCarFuelPredictionProvider =
    FutureProvider<FuelPrediction?>((ref) async {
      ref.watch(preferencesEpochProvider);
      final car = await ref.watch(appliedCarProvider.future);
      if (car?.id == null) {
        return null;
      }
      return ref
          .watch(fuelRepositoryProvider)
          .getFuelPredictionForCar(car!.id!);
    });

/// 某辆车的加油记录全量列表（按日期、里程、id 升序——满箱段油耗口径的
/// 锚定顺序，ADR 0014），按车 id 缓存的 family。加载、竞态、缓存由
/// Riverpod 接管，写库后随车辆数据纪元 bump 整族重查（家族实例无人监听
/// 即销毁，下次 watch 重查；ADR 0017 修订节，同项目 family 的约定）。
final fuelRecordsForCarProvider =
    FutureProvider.family<List<FuelRecord>, int>((ref, carId) {
  ref.watch(vehicleDataEpochProvider);
  return ref.watch(fuelRepositoryProvider).listFuelRecordsForCar(carId);
});

/// 应用车辆的加油记录全量列表。仿 [appliedCarFuelPredictionProvider] 的
/// 派生模式：只承载"当前应用车辆解析 + 无车返回空列表"两条规则，
/// 数据拉取统一走 [fuelRecordsForCarProvider]。build 首行 watch 车辆
/// 数据纪元（显式声明失效来源，不依赖上游 family 换新实例的隐式不等性）。
final appliedCarFuelRecordsProvider =
    FutureProvider<List<FuelRecord>>((ref) async {
      ref.watch(vehicleDataEpochProvider);
      final car = await ref.watch(appliedCarProvider.future);
      if (car?.id == null) {
        return const [];
      }
      return ref.watch(fuelRecordsForCarProvider(car!.id!).future);
    });

/// 全局生效的"今天"：手动日期优先，否则系统今天。
/// 所有业务日期口径（提醒进度、记录表单默认日期、snooze/ack 判断）都用它，
/// 只有停车倒计时和系统通知调度时刻用真实时间（tz.TZDateTime.now）。
final effectiveTodayProvider = FutureProvider<LocalDate>((ref) async {
  ref.watch(preferencesEpochProvider);
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
/// 注意这里显式 await bootstrap 完成，保证车型目录已入库；build 首行
/// watch 车辆数据纪元（写库后的重查随纪元 bump，ADR 0017 修订节）。
final vehicleModelsProvider = FutureProvider<List<VehicleModel>>((ref) async {
  ref.watch(vehicleDataEpochProvider);
  await ref.watch(defaultMaintenanceBootstrapProvider.future);
  return ref.watch(builtInCatalogRepositoryProvider).listVehicleModels();
});

/// 添加车辆向导第二步的默认保养项目模板，按"品牌·车型·动力类型"缓存的
/// family（key 是 Dart record，结构化相等）。解析规则只此一份：仓库的
/// resolveDefaultItems（ensureBootstrapData + 车型专属优先回退通用，
/// ADR 0004）。模板是内置只读数据，不存在"写库后失效"问题，family
/// 常驻缓存即可；向导 State 只保留"模板 → 草稿"的转换。
final defaultItemsTemplateProvider = FutureProvider.family<
  List<VehicleDefaultMaintenanceItem>,
  ({String brand, String model, PowertrainType powertrain})
>((ref, key) {
  return ref
      .watch(builtInCatalogRepositoryProvider)
      .resolveDefaultItems(
        brand: key.brand,
        model: key.model,
        selectedPowertrain: key.powertrain,
      );
});

/// 当前用户所有车辆列表。显式 await bootstrap 完成（依赖显式化，R29）：
/// bootstrap 只写车型目录/默认模板两张内置表、不写 cars 表，
/// 行为与原先"只借用失效信号"等价，但依赖关系在代码里一目了然。
/// build 首行 watch 车辆数据纪元（写库后的重查随纪元 bump，ADR 0017
/// 修订节）。
final carsProvider = FutureProvider<List<Car>>((ref) async {
  ref.watch(vehicleDataEpochProvider);
  await ref.watch(defaultMaintenanceBootstrapProvider.future);
  return ref.watch(lunioRepositoryProvider).listCars();
});

/// 当前"应用车辆"（正在被提醒页/记录页展示的车）。
/// 显式 await carsProvider（依赖显式化，R29）；实际取值走
/// repository.getAppliedCar()，其内部按 AppliedCarRules 回退：
/// 偏好里的 appliedCarId 存在且有效则用它，否则回退第一辆车，无车返回 null。
/// build 首行 watch 车辆数据纪元（切换应用车辆/删车等写点 bump 后重算）。
final appliedCarProvider = FutureProvider<Car?>((ref) async {
  ref.watch(vehicleDataEpochProvider);
  await ref.watch(carsProvider.future);
  return ref.watch(lunioRepositoryProvider).getAppliedCar();
});

/// 某辆车的保养项目列表（含启用/停用状态），按车 id 缓存的 family。
/// 项目管理 sheet（可管任意一辆车，不限当前应用车辆）与记录表单行内
/// 新增共用这一份拉取逻辑；加载、竞态、缓存由 Riverpod 接管，写库后
/// 随车辆数据纪元 bump 整族重查（家族实例无人监听即销毁，下次 watch
/// 重查；ADR 0017 修订节）。
final maintenanceItemsForCarProvider =
    FutureProvider.family<List<MaintenanceItem>, int>((ref, carId) {
  ref.watch(vehicleDataEpochProvider);
  return ref.watch(lunioRepositoryProvider).listMaintenanceItemsForCar(carId);
});

/// 应用车辆的保养项目列表（含启用/停用状态）。只承载"当前应用车辆
/// 解析 + 无车返回空列表"两条规则，数据拉取统一走
/// [maintenanceItemsForCarProvider]；build 首行 watch 车辆数据纪元
/// （失效来源显式声明，与记录/加油派生同款）。
final appliedCarMaintenanceItemsProvider =
    FutureProvider<List<MaintenanceItem>>((ref) async {
      ref.watch(vehicleDataEpochProvider);
      final car = await ref.watch(appliedCarProvider.future);
      if (car?.id == null) {
        return const [];
      }
      return ref.watch(maintenanceItemsForCarProvider(car!.id!).future);
    });

/// 某辆车的保养记录全量列表，按车 id 缓存的 family（无分页）。
/// 应用车辆记录派生（[appliedCarRecordsProvider]，数据束与费用统计页
/// 经它消费）等按车消费者共用；
/// 加载、竞态、缓存由 Riverpod 接管，写库后随车辆数据纪元 bump 整族
/// 重查（同项目 family 的约定；ADR 0017 修订节）。
final recordsForCarProvider =
    FutureProvider.family<List<MaintenanceRecord>, int>((ref, carId) {
  ref.watch(vehicleDataEpochProvider);
  return ref
      .watch(lunioRepositoryProvider)
      .listMaintenanceRecordsForCar(carId);
});

/// 应用车辆的保养记录全量列表（记录页与提醒计算共用，无分页）。
/// 仿 [appliedCarMaintenanceItemsProvider] 的派生模式：只承载"当前应用
/// 车辆解析 + 无车返回空列表"两条规则，数据拉取统一走
/// [recordsForCarProvider]（与项目/加油派生同构——此前这里直查仓库、
/// 不 watch 按车 family，是三个 applied 派生里的例外写法，2026-10-01
/// 随数据束收编统一）；build 首行 watch 车辆数据纪元（失效来源显式
/// 声明，与项目/加油派生同款）。
final appliedCarRecordsProvider =
    FutureProvider<List<MaintenanceRecord>>((ref) async {
      ref.watch(vehicleDataEpochProvider);
      final car = await ref.watch(appliedCarProvider.future);
      if (car?.id == null) {
        return const [];
      }
      return ref.watch(recordsForCarProvider(car!.id!).future);
    });

/// 应用车辆数据束：当前应用车辆 + 项目清单 + 保养记录 + 生效今天
/// 四件套一次拿齐（CONTEXT.md 词条「应用车辆数据束」）。
///
/// 就绪语义只有这一份实现：
///  - 任一上游未就绪（loading/error）→ 数据束整体未就绪（AsyncValue
///    的 loading/error，消费方 AsyncValue.when 收口）；
///  - 无车是合法空态：car = null 时仍是 data 态（items/records 按
///    applied 派生的既有规则给空表），不是 loading——新车主不阻塞页面。
///
/// 谁该 watch 它：一切"按当前应用车辆消费车况数据"的页面/控制器/表单
/// （提醒行组装、记录页、费用统计页、通知同步控制器、小组件快照
/// 控制器），不要再各自手抄"逐个 watch、loading 折叠成 null、生效今天
/// 兜底系统日期"的装载策略。不装进来的：通知设置与停车倒计时（各自
/// 域内的偏好 provider，控制器自己监听）；加油记录（加油域，ADR 0015，
/// 消费方按域单独 watch）。
///
/// 边界（与车辆数据纪元的分工）：数据束是读侧接缝（watch 哪些上游），
/// 纪元是写侧失效机制（写库点 bump）——本 provider 不直接读库、不
/// watch 纪元，bump 后经上游（四个上游各自的 watch 行）传导重算；偏好
/// 纪元边界不动（today 上游自己 watch 偏好纪元，属既有行为）。
class AppliedCarBoard {
  const AppliedCarBoard({
    required this.car,
    required this.items,
    required this.records,
    required this.today,
  });

  /// 当前应用车辆；null = 没有车（合法空态）。
  final Car? car;

  /// 应用车辆的保养项目清单（无车为空表）。
  final List<MaintenanceItem> items;

  /// 应用车辆的保养记录全量列表（无车为空表）。
  final List<MaintenanceRecord> records;

  /// 生效今天（手动日期优先，否则系统今天）。
  final LocalDate today;
}

/// 数据束 provider：顺序 await 四个上游（车辆/项目/记录/生效今天），
/// 全部落定才算就绪。写库后的刷新随车辆数据纪元 bump 传导：上游
/// （appliedCar / applied 派生及其按车 family）各自 build 首行 watch
/// 纪元，重算沿依赖链传导到数据束；数据束自身不 watch 纪元（不读库，
/// 机制测试锁住上游的 watch 行不许删）。
final appliedCarBoardProvider = FutureProvider<AppliedCarBoard>((ref) async {
  final car = await ref.watch(appliedCarProvider.future);
  final items = await ref.watch(appliedCarMaintenanceItemsProvider.future);
  final records = await ref.watch(appliedCarRecordsProvider.future);
  final today = await ref.watch(effectiveTodayProvider.future);
  return AppliedCarBoard(
    car: car,
    items: items,
    records: records,
    today: today,
  );
});

/// 费用统计页要用的全部数据（/cost-stats 一次拿齐）：当前应用车辆名
/// （null = 无车）、该车保养记录、加油记录、项目清单（项目名解析用）、
/// 生效今天。2026-10-01 自 cost_stats_page.dart 迁入，与数据束同款
/// "数据类 + provider 同处"的写法。
class CostStatsPageData {
  const CostStatsPageData({
    required this.carName,
    required this.records,
    required this.fuelRecords,
    required this.items,
    required this.today,
  });

  /// 当前应用车辆显示名（"品牌 型号"）；null = 没有应用车辆（无车）。
  final String? carName;

  final List<MaintenanceRecord> records;

  /// 当前应用车辆的加油记录（加油费用卡数据源；无车为空表——
  /// [appliedCarFuelRecordsProvider] 的派生规则，页面不再手抄）。
  final List<FuelRecord> fuelRecords;
  final List<MaintenanceItem> items;
  final LocalDate today;
}

/// 费用统计页数据接缝：车/记录/项目/生效今天经 [appliedCarBoardProvider]
/// 拿齐；加油记录经 [appliedCarFuelRecordsProvider] 派生（与记录页头部
/// 汇总行、加油记录卡同一条派生链，"当前应用车辆解析 + 无车空表"语义
/// 只有那一份）。就绪语义随上游传导：数据束任一上游 loading/error →
/// 本 provider 同态 loading/error——费用统计页 watch 这一个 provider
/// 单门卫收口即可（2026-10-01 并轨，此前页面文件里双层门卫 + 手抄
/// 无车分支）。失效随家族走——写库后车辆数据纪元 bump，上游各自 watch
/// 纪元重算并传导到这里（本 provider 不读库、不 watch 纪元）。
final costStatsDataProvider = FutureProvider<CostStatsPageData>((ref) async {
  final board = await ref.watch(appliedCarBoardProvider.future);
  final fuelRecords = await ref.watch(appliedCarFuelRecordsProvider.future);
  final car = board.car;
  return CostStatsPageData(
    carName: car == null ? null : '${car.brand} ${car.model}',
    records: board.records,
    fuelRecords: fuelRecords,
    items: board.items,
    today: board.today,
  );
});

/// 通知服务：生产装配为全局单例；测试可整体覆盖为新实例
/// （服务是普通可实例化类，实例间不共享状态）。
final lunioNotificationServiceProvider = Provider<LunioNotificationService>((
  ref,
) {
  return LunioNotificationService.instance;
});

/// 停车实时活动桥：生产装配真实通道实现；测试可整体覆盖为假子类。
/// 非 iOS 平台上方法自禁用（见桥文件头），Android 行为零变化。
final nativeLiveActivitiesProvider = Provider<NativeLiveActivities>((ref) {
  return NativeLiveActivities();
});

/// 桌面小组件快照桥：生产装配真实通道实现；测试可整体覆盖为假实现。
/// 非 iOS 平台上方法自禁用（见桥文件头），Android 行为零变化。
final nativeWidgetsProvider = Provider<NativeWidgets>((ref) {
  return NativeWidgets();
});

/// 全量失效：恢复备份 / 清空数据后调用，让所有 FutureProvider 重新查库。
/// bootstrap 单独逐出（它不 watch 车辆数据纪元——目录对账的幂等重灌
/// 只有这一个触发点，恢复/清空后必须显式失效才重灌）；parkingCountdown
/// 单独逐出（它不走任何纪元，写点直失效模型）；两个数据纪元各 bump
/// 一次（车辆/项目/记录/加油四张业务表 + 偏好表的派生缓存全体作废）。
void invalidateAllAppDataProviders(WidgetRef ref) {
  ref.invalidate(defaultMaintenanceBootstrapProvider);
  ref.invalidate(parkingCountdownProvider);
  ref.read(vehicleDataEpochProvider.notifier).bump();
  ref.read(preferencesEpochProvider.notifier).bump();
}

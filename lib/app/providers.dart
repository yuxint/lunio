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
// Repository 的写方法（增删改）**不会**主动刷新任何缓存，
// 统一由 UI 层在写库成功后调用 invalidateVehicleProviders /
// invalidatePreferenceProviders / invalidateAllAppDataProviders
// 手动逐出相关缓存，触发 FutureProvider 重新查库 → UI 自动重建。
// 这是"手动失效"模式：漏调 invalidate 会导致跨页面数据陈旧。
//
// ## 依赖关系图
// ```text
// appDatabaseProvider（惰性建库/连库）
//   └─ lunioRepositoryProvider（唯一 Repository ≈ Service+DAO）
//        ├─ developerModeProvider ──> manualDatePreferenceProvider
//        ├─ themeModePreferenceProvider（主题）
//        ├─ notificationSettingsProvider（4 个通知偏好串行读）
//        ├─ parkingCountdownProvider（停车倒计时，存偏好表）
//        ├─ effectiveTodayProvider（手动日期 ?? 系统今天）
//        └─ defaultMaintenanceBootstrapProvider（首启灌入车型库/默认项目）
//             ├─ vehicleModelsProvider
//             └─ carsProvider ──> appliedCarProvider
//                                  ├─ appliedCarMaintenanceItemsProvider
//                                  └─ appliedCarRecordsProvider
// ```
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date/app_date_context.dart';
import '../core/date/local_date.dart';
import '../data/database/app_database.dart';
import '../data/repositories/lunio_repository.dart';
import '../domain/entities/car.dart';
import '../domain/entities/maintenance_item.dart';
import '../domain/entities/maintenance_record.dart';
import '../domain/entities/notification_settings.dart';
import '../domain/entities/parking_countdown.dart';
import '../domain/entities/vehicle_model.dart';

/// 应用日期上下文：目前只用它读"系统真实当前时间"（停车倒计时用）。
/// 手动日期（开发者模式）不会写进这里，而是走 [manualDatePreferenceProvider]，
/// 两者在 [effectiveTodayProvider] 处汇合，形成"业务日期/真实时间"双轨。
final appDateContextProvider = Provider<AppDateContext>(
  (ref) => AppDateContext.system(),
);

/// 开发者模式开关（Boolean 存字符串 'true'/'false'）。
/// 入口在"我的"页版本号连点 5 次（profile_page.dart），控制手动日期行是否显示。
final developerModeProvider = FutureProvider<bool>((ref) async {
  final repository = ref.watch(lunioRepositoryProvider);
  final value = await repository.getPreferenceValue('developerModeEnabled');
  return value == 'true';
});

/// 手动覆盖日期（开发者模式专属）。三层条件全满足才生效：
/// 开发者模式开 → 手动日期开关开 → manualDate 偏好存在且可解析。
/// 任何一层不满足返回 null（即使用系统真实日期）。
final manualDatePreferenceProvider = FutureProvider<LocalDate?>((ref) async {
  final repository = ref.watch(lunioRepositoryProvider);
  final developerModeEnabled = await ref.watch(developerModeProvider.future);
  if (!developerModeEnabled) {
    return null;
  }
  final enabled = await repository.getPreferenceValue('manualDateEnabled');
  if (enabled != 'true') {
    return null;
  }
  final value = await repository.getPreferenceValue('manualDate');
  if (value == null) {
    return null;
  }
  return LocalDate.tryParse(value);
});

/// 主题模式偏好：'light' / 'dark' / 其他（含 null）都按 system 处理。
/// 被 LunioApp.watch，写入后经 invalidatePreferenceProviders 刷新。
final themeModePreferenceProvider = FutureProvider<ThemeMode>((ref) async {
  final repository = ref.watch(lunioRepositoryProvider);
  final value = await repository.getPreferenceValue('themeMode');
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

/// 通知设置：4 个偏好 key 串行读取（systemNotificationsEnabled /
/// inAppNotificationsEnabled / maintenanceDueEnabled / maintenanceDueRepeat）。
/// 取值约定：`!= 'false'` ——即从未设置过时默认开启。
final notificationSettingsProvider = FutureProvider<LunioNotificationSettings>((
  ref,
) async {
  final repository = ref.watch(lunioRepositoryProvider);
  return LunioNotificationSettings(
    systemNotificationsEnabled:
        await repository.getPreferenceValue('systemNotificationsEnabled') !=
        'false',
    inAppNotificationsEnabled:
        await repository.getPreferenceValue('inAppNotificationsEnabled') !=
        'false',
    maintenanceDueEnabled:
        await repository.getPreferenceValue('maintenanceDueEnabled') != 'false',
    dueRepeatFrequency: ReminderRepeatFrequencyCodec.parse(
      await repository.getPreferenceValue('maintenanceDueRepeat'),
    ),
  );
});

/// 停车倒计时：临时状态，以 JSON 存在偏好表 `parkingCountdown` key 下，
/// 不进入 JSON 备份（备份契约见 backup_codec.dart）。
final parkingCountdownProvider = FutureProvider<ParkingCountdown?>((ref) {
  return ref.watch(lunioRepositoryProvider).getParkingCountdown();
});

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

/// 唯一 Repository：所有数据库读写、事务、备份恢复的出口。
/// Java 对照：一个兼具 Service 与 DAO 职责的 Bean。
final lunioRepositoryProvider = Provider<LunioRepository>((ref) {
  return LunioRepository(ref.watch(appDatabaseProvider));
});

/// 首启/升级引导：把 asset 里的内置车型目录与默认保养项目模板
/// 同步进数据库（幂等，按 catalogId upsert）。AppShell 首帧 watch 触发。
final defaultMaintenanceBootstrapProvider = FutureProvider<void>((ref) {
  return ref.watch(lunioRepositoryProvider).ensureBootstrapData();
});

/// 车型库（约 190 个车型），供添加车辆向导的品牌/车型选择器使用。
/// 注意这里显式 await bootstrap 完成，保证车型目录已入库。
final vehicleModelsProvider = FutureProvider<List<VehicleModel>>((ref) async {
  await ref.watch(defaultMaintenanceBootstrapProvider.future);
  return ref.watch(lunioRepositoryProvider).listVehicleModels();
});

/// 当前用户所有车辆列表。这里对 bootstrap 只 watch 不 await：
/// bootstrap 只写车型目录/默认模板两张内置表、不写 cars 表，
/// 因此 cars 查询与 bootstrap 并行执行是安全的（只借用它的失效信号）。
final carsProvider = FutureProvider<List<Car>>((ref) {
  ref.watch(defaultMaintenanceBootstrapProvider);
  return ref.watch(lunioRepositoryProvider).listCars();
});

/// 当前"应用车辆"（正在被提醒页/记录页展示的车）。
/// watch carsProvider 只是为了借用它的失效信号（cars 变 → 重算本 provider）；
/// 实际取值走 repository.getAppliedCar()，其内部按 AppliedCarRules 回退：
/// 偏好里的 appliedCarId 存在且有效则用它，否则回退第一辆车，无车返回 null。
final appliedCarProvider = FutureProvider<Car?>((ref) {
  ref.watch(carsProvider);
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

/// 车辆/项目/记录相关缓存整体失效（写库后由 UI 调用）。
/// 逐出的顺序无关紧要，Riverpod 会在下一帧统一重算被 watch 的 provider。
void invalidateVehicleProviders(WidgetRef ref) {
  ref.invalidate(carsProvider);
  ref.invalidate(vehicleModelsProvider);
  ref.invalidate(appliedCarProvider);
  ref.invalidate(appliedCarMaintenanceItemsProvider);
  ref.invalidate(appliedCarRecordsProvider);
}

/// 偏好类缓存整体失效：开发者模式、手动日期、生效日期、主题、通知设置。
void invalidatePreferenceProviders(WidgetRef ref) {
  ref.invalidate(developerModeProvider);
  ref.invalidate(manualDatePreferenceProvider);
  ref.invalidate(effectiveTodayProvider);
  ref.invalidate(themeModePreferenceProvider);
  ref.invalidate(notificationSettingsProvider);
}

/// 全量失效：恢复备份 / 清空数据后调用，让所有 FutureProvider 重新查库。
/// parkingCountdown 单独逐出（它不在上面两个方法里）。
void invalidateAllAppDataProviders(WidgetRef ref) {
  ref.invalidate(defaultMaintenanceBootstrapProvider);
  ref.invalidate(parkingCountdownProvider);
  invalidateVehicleProviders(ref);
  invalidatePreferenceProviders(ref);
}

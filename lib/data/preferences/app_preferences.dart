// 偏好门面（LunioPreferences）：app_preferences 表的唯一读写出口。
//
// ≈ Java 里把散落各处的 properties key 收进一个 @Repository 配置类：
// key 字符串、'true'/'false' 编码、默认值语义、JSON 编解码全部收拢在
// 本模块，调用方只见 typed 方法，不再拼魔法字符串、不再各自解析。
// 油价缓存/手填油价两个临时 key 除外——它们属于加油域的业务数据，
// 由 FuelRepository 经本模块的 readRaw/writeRaw 原语存取（key 常量
// 定义在 FuelRepository 上）。
//
// 职责边界：
//  - 只做"key ↔ 类型"的存取与编解码，不做业务判断（比如"开发者模式
//    关时手动日期不生效"由 provider 组合决定，本模块不管）；
//  - 不做缓存失效——写库后 invalidate provider 仍是调用方（动作层/
//    协调器）的责任，与本仓库其余部分同一约定；
//  - 抑制类 key（"稍后提醒"/"知道了"）的前缀常量在这里登记：写入方
//    （通知协调器拼 key）与清除方（恢复备份按前缀删）共用同一组常量，
//    不会各自漂移。
//
// ⚠ key 字符串与取值语义（'true' 才算开 / '!= false' 默认开）是持久化
// 契约，改动会让老用户已保存的偏好失效——改前先看 AGENTS.md 的偏好
// key 清单与备份契约。
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../../core/date/local_date.dart';
import '../../core/id/snowflake_id_generator.dart';
import '../../domain/entities/notification_settings.dart';
import '../../domain/entities/parking_countdown.dart' as domain;
import '../../domain/entities/fuel_price.dart' as domain;
import '../database/app_database.dart';

class LunioPreferences {
  /// 构造时注入数据库连接（无状态模块，同库多实例等价）。
  LunioPreferences(this.database);

  final AppDatabase database;

  // ---------------- key 常量（唯一事实来源，清单另见 AGENTS.md）----------------

  /// 当前应用车辆 id。
  static const appliedCarIdKey = 'appliedCarId';

  /// 开发者模式开关（'true' 才算开）。
  static const developerModeEnabledKey = 'developerModeEnabled';

  /// 手动日期开关 + 值（开发者模式专属，两个 key 成对读写）。
  static const manualDateEnabledKey = 'manualDateEnabled';
  static const manualDateKey = 'manualDate';

  /// 主题模式（'light' / 'dark' / 其他含 null 一律按 system）。
  static const themeModeKey = 'themeMode';

  /// 通知设置三键 + 系统权限"已请求过"标记。
  static const systemNotificationsEnabledKey = 'systemNotificationsEnabled';
  static const inAppNotificationsEnabledKey = 'inAppNotificationsEnabled';
  static const maintenanceDueRepeatKey = 'maintenanceDueRepeat';
  static const systemNotificationPermissionRequestedKey =
      'systemNotificationPermissionRequested';

  /// 加油预测开关与全局省份/油品选择（省份/油品进备份）。
  static const fuelPredictionEnabledKey = 'fuelPredictionEnabled';
  static const fuelProvinceKey = 'fuelProvince';
  static const fuelGradeKey = 'fuelGrade';

  /// 停车倒计时（JSON，临时数据不进备份）。
  static const _parkingCountdownKey = 'parkingCountdown';

  // ---- 提醒抑制类偏好 key 前缀（单一事实来源）----
  // 通知协调器用前缀拼 key 写入；恢复备份按同一组前缀 like 删除。
  // 两处共用这里的常量，避免"写入的 key"与"清除的前缀"漂移。

  /// 保养项 snooze 截止日前缀（按项目 id 区分）。
  static const maintenanceReminderSnoozedUntilPrefix =
      'maintenanceReminderSnoozedUntil:';

  /// 里程更新 snooze 截止日前缀（按车辆 id 区分）。
  static const mileageUpdateSnoozedUntilPrefix =
      'mileageUpdateSnoozedUntil:';

  /// 保养项应用内提醒当日 ack 前缀（按项目 id 区分）。
  static const maintenanceInAppReminderAcknowledgedOnPrefix =
      'maintenanceInAppReminderAcknowledgedOn:';

  /// 里程更新应用内提醒当日 ack 前缀（按车辆 id 区分）。
  static const mileageUpdateInAppAcknowledgedOnPrefix =
      'mileageUpdateInAppAcknowledgedOn:';

  /// 上面四个前缀的清单（恢复备份时逐前缀 like 删除）。
  static const reminderSuppressionKeyPrefixes = [
    maintenanceReminderSnoozedUntilPrefix,
    mileageUpdateSnoozedUntilPrefix,
    maintenanceInAppReminderAcknowledgedOnPrefix,
    mileageUpdateInAppAcknowledgedOnPrefix,
  ];

  // ---------------- 通用 KV 原语 ----------------
  // 仅供本模块与加油域（FuelRepository 存 JSON 临时数据）使用。

  /// 按 key 取原始字符串（不存在返回 null）。
  Future<String?> readRaw(String key) async {
    final row = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 批量取原始字符串：单条 IN 查询一次取回多个 key（R27）。
  /// 返回 Map：存在的 key → value；不存在的 key 不出现在返回值里。
  Future<Map<String, String?>> readRawAll(List<String> keys) async {
    if (keys.isEmpty) {
      return const {};
    }
    final rows =
        await (database.select(
          database.appPreferences,
        )..where((pref) => pref.key.isIn(keys))).get();
    return {for (final row in rows) row.key: row.value};
  }

  /// 写原始字符串（value 为 null 等价删除该 key）。
  Future<void> writeRaw(String key, String? value) async {
    return _writeRaw(key, value);
  }

  /// 批量写原始字符串：一个事务内逐 key upsert（R27），全成功或全回滚。
  Future<void> writeRawAll(Map<String, String?> values) {
    return database.transaction(() async {
      for (final entry in values.entries) {
        await _writeRaw(entry.key, entry.value);
      }
    });
  }

  /// 删除整张偏好表（清空数据专用；恢复备份不走这里——它保留偏好）。
  Future<void> deleteAll() {
    return database.delete(database.appPreferences).go();
  }

  /// 按前缀批量删除（恢复备份清除抑制 key 专用）。
  Future<void> _deleteByPrefix(String prefix) {
    return (database.delete(
      database.appPreferences,
    )..where((pref) => pref.key.like('$prefix%'))).go();
  }

  /// 偏好 upsert：null 删行；无则插入、有则更新（syncStatus 记
  /// pendingUpdate、updatedAt 刷新，沿用全库约定）。
  /// ⚠ select-then-insert 非原子（单 isolate 下窗口极小）。
  Future<void> _writeRaw(String key, String? value) async {
    if (value == null) {
      await (database.delete(
        database.appPreferences,
      )..where((pref) => pref.key.equals(key))).go();
      return;
    }
    final existing = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals(key))).getSingleOrNull();
    final now = DateTime.now().toIso8601String();
    if (existing == null) {
      await database
          .into(database.appPreferences)
          .insert(
            AppPreferencesCompanion.insert(
              id: Value(SnowflakeIdGenerator.instance.next()),
              key: key,
              value: Value(value),
              syncStatus: const Value('pendingUpdate'),
              updatedAt: now,
            ),
          );
      return;
    }
    await (database.update(
      database.appPreferences,
    )..where((pref) => pref.key.equals(key))).write(
      AppPreferencesCompanion(
        value: Value(value),
        syncStatus: const Value('pendingUpdate'),
        updatedAt: Value(now),
      ),
    );
  }

  // ---------------- 应用车辆 ----------------

  /// 读当前应用车辆 id（未设置或非数字返回 null）。
  Future<int?> getAppliedCarId() async {
    return int.tryParse(await readRaw(appliedCarIdKey) ?? '');
  }

  /// 写当前应用车辆 id（null = 清除）。事务内外均可调用（同一连接的
  /// 环境事务）。
  Future<void> setAppliedCarId(int? carId) {
    return _writeRaw(appliedCarIdKey, carId?.toString());
  }

  /// 仅当偏好当前指向 [carId] 时清除（删除车辆的级联清理用：指向
  /// 其他车时不动，避免多余的写库）。
  Future<void> clearAppliedCarIdIfValue(int carId) {
    return (database.delete(database.appPreferences)..where(
          (pref) =>
              pref.key.equals(appliedCarIdKey) &
              pref.value.equals('$carId'),
        ))
        .go();
  }

  // ---------------- 开发者模式 / 手动日期 ----------------

  /// 开发者模式开关（'true' 才算开，默认关）。
  Future<bool> getDeveloperModeEnabled() async {
    return await readRaw(developerModeEnabledKey) == 'true';
  }

  /// 写开发者模式开关（'true'/'false'）。只写库，失效
  /// developerModeProvider 由调用方负责。
  Future<void> setDeveloperModeEnabled(bool enabled) {
    return _writeRaw(developerModeEnabledKey, enabled ? 'true' : 'false');
  }

  /// 手动日期开关是否打开。
  Future<bool> isManualDateEnabled() async {
    return await readRaw(manualDateEnabledKey) == 'true';
  }

  /// 读手动日期值（未设置或无法解析返回 null；开关状态由调用方组合）。
  Future<LocalDate?> getManualDate() async {
    final value = await readRaw(manualDateKey);
    if (value == null) {
      return null;
    }
    return LocalDate.tryParse(value);
  }

  /// 成对写手动日期：date 为 null 时关闭开关并清值，否则打开开关写入。
  /// （两个 key 的成对关系是本模块的契约，调用方不再各自记得写两个。）
  Future<void> saveManualDateOverride(LocalDate? date) {
    return writeRawAll({
      manualDateEnabledKey: date == null ? 'false' : 'true',
      manualDateKey: date?.toString(),
    });
  }

  // ---------------- 主题 ----------------

  /// 读主题模式：'light'/'dark' 之外（含 null）一律按 system。
  Future<ThemeMode> getThemeMode() async {
    return switch (await readRaw(themeModeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  /// 写主题模式（编码见 [getThemeMode] 的反向映射）。只写库，失效
  /// themeModePreferenceProvider 由调用方负责。
  Future<void> setThemeMode(ThemeMode mode) {
    return _writeRaw(themeModeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  // ---------------- 通知设置 ----------------

  /// 读通知设置：3 个 key 一条 IN 查询（R27）。
  /// 取值约定：`!= 'false'`——从未设置过时默认开启。
  /// 保养到期提醒是产品核心能力，不提供关闭入口（R5）。
  Future<LunioNotificationSettings> readNotificationSettings() async {
    final values = await readRawAll([
      systemNotificationsEnabledKey,
      inAppNotificationsEnabledKey,
      maintenanceDueRepeatKey,
    ]);
    return LunioNotificationSettings(
      systemNotificationsEnabled:
          values[systemNotificationsEnabledKey] != 'false',
      inAppNotificationsEnabled:
          values[inAppNotificationsEnabledKey] != 'false',
      dueRepeatFrequency: ReminderRepeatFrequencyCodec.parse(
        values[maintenanceDueRepeatKey],
      ),
    );
  }

  /// 一个事务内批量写通知设置 3 个 key（R27）。
  Future<void> saveNotificationSettings(LunioNotificationSettings settings) {
    return writeRawAll({
      systemNotificationsEnabledKey: settings.systemNotificationsEnabled
          .toString(),
      inAppNotificationsEnabledKey: settings.inAppNotificationsEnabled
          .toString(),
      maintenanceDueRepeatKey: settings.dueRepeatFrequency.value,
    });
  }

  /// 系统通知开关（语义同上：!= 'false' 默认开）。
  Future<bool> getSystemNotificationsEnabled() async {
    return await readRaw(systemNotificationsEnabledKey) != 'false';
  }

  /// 写系统通知开关（编码同读取约定：开 'true' / 关 'false'）。只写库，
  /// 失效 notificationSettingsProvider 由调用方负责；被拒时回写 false
  /// 的场景见通知协调器。
  Future<void> setSystemNotificationsEnabled(bool enabled) {
    return _writeRaw(
      systemNotificationsEnabledKey,
      enabled ? 'true' : 'false',
    );
  }

  /// 应用内提醒弹窗开关。
  Future<bool> getInAppNotificationsEnabled() async {
    return await readRaw(inAppNotificationsEnabledKey) != 'false';
  }

  /// 写应用内提醒弹窗开关（编码同上）。只写库，失效
  /// notificationSettingsProvider 由调用方负责。
  Future<void> setInAppNotificationsEnabled(bool enabled) {
    return _writeRaw(inAppNotificationsEnabledKey, enabled ? 'true' : 'false');
  }

  /// 系统通知权限是否已请求过（'true' 才算请求过，默认未请求）。
  Future<bool> isSystemNotificationPermissionRequested() async {
    return await readRaw(systemNotificationPermissionRequestedKey) == 'true';
  }

  /// 标记"系统通知权限已请求过"（只写一次语义由调用方保证——首启链
  /// 先读本标记再决定是否请求）。
  Future<void> markSystemNotificationPermissionRequested() {
    return _writeRaw(systemNotificationPermissionRequestedKey, 'true');
  }

  // ---------------- 加油预测开关 / 省份 / 油品 ----------------

  /// 加油预测功能开关（'true' 才算开，默认关）。
  Future<bool> getFuelPredictionEnabled() async {
    return await readRaw(fuelPredictionEnabledKey) == 'true';
  }

  /// 写加油预测功能开关。只写库，失效 fuelPredictionEnabledProvider 由
  /// 调用方负责（开关变化决定底部"加油"tab 是否出现）。
  Future<void> setFuelPredictionEnabled(bool enabled) {
    return _writeRaw(fuelPredictionEnabledKey, enabled ? 'true' : 'false');
  }

  /// 省份（未设置返回 null；默认值"湖北"由数据源层提供，这里不掺业务默认）。
  Future<String?> getFuelProvince() {
    return readRaw(fuelProvinceKey);
  }

  /// 写省份（原样存字符串，不校验取值——取值范围由数据源层保证）。
  /// 进备份；只写库，失效 fuelProvinceProvider 由调用方负责。
  Future<void> setFuelProvince(String province) {
    return _writeRaw(fuelProvinceKey, province);
  }

  /// 油品编号（未设置或无法解析回退 92#，产品默认）。
  Future<domain.FuelGrade> getFuelGrade() async {
    final code = await readRaw(fuelGradeKey);
    return domain.FuelGrade.tryParse(code ?? '') ?? domain.FuelGrade.gasoline92;
  }

  /// 写油品（存 [domain.FuelGrade.code]）。进备份；只写库，失效
  /// fuelGradeProvider 由调用方负责。
  Future<void> setFuelGrade(domain.FuelGrade grade) {
    return _writeRaw(fuelGradeKey, grade.code);
  }

  // ---------------- 停车倒计时（临时偏好，不进备份）----------------

  /// 读停车倒计时（偏好里的 JSON）。
  /// JSON 损坏时打日志并返回 null（R14：不静默吞异常；坏数据仍留在
  /// 库里，由下次保存倒计时覆盖修复）。
  Future<domain.ParkingCountdown?> getParkingCountdown() async {
    final value = await readRaw(_parkingCountdownKey);
    if (value == null) {
      return null;
    }
    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      return domain.ParkingCountdown.fromJson(json);
    } catch (error) {
      developer.log(
        'LunioPreferences: 停车倒计时偏好 JSON 损坏，按无倒计时处理：$error',
        name: 'lunio.repository',
      );
      return null;
    }
  }

  /// 保存停车倒计时（序列化为 JSON 存偏好）。只写库——系统通知的调度/
  /// 取消由通知协调器负责。
  Future<void> saveParkingCountdown(domain.ParkingCountdown countdown) {
    return _writeRaw(_parkingCountdownKey, jsonEncode(countdown.toJson()));
  }

  /// 清除停车倒计时（删 key）。
  Future<void> clearParkingCountdown() {
    return _writeRaw(_parkingCountdownKey, null);
  }

  // ---------------- 提醒抑制 key 清理 ----------------

  /// 按登记的前缀清除全部抑制 key（恢复备份专用：恢复出来的车/项目拿
  /// 全新雪花 id，旧 snooze/ack 与新数据已无语义关联）。
  Future<void> clearReminderSuppressionKeys() async {
    for (final prefix in reminderSuppressionKeyPrefixes) {
      await _deleteByPrefix(prefix);
    }
  }
}

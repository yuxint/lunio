// 通知协调器（LunioNotificationCoordinator）：通知域的规则拥有者。
// ≈ Spring 里一个领域 Service：界面只报告"发生了什么 / 要保存什么设置"，
// 权限真值对账、通知清扫的具体协议全部内聚在这里，调用方不再接触
// 偏好 key 字符串、通知 id 分段和同步代数。
//
// 拥有的偏好 key（唯一写者，读侧 notificationSettingsProvider 的字符串
// 必须与这里保持一致）：
//  - systemNotificationsEnabled / systemNotificationPermissionRequested；
//  - inAppNotificationsEnabled / maintenanceDueRepeat（经
//    saveNotificationSettings 批量写）；
//  - 抑制类 key（"稍后提醒"/"知道了"，前缀常量以 LunioRepository 为
//    单一事实来源，恢复备份按同组前缀清除）。
//
// 与 NotificationSyncController 的分工：controller 保留被动监听外壳
// （订阅 provider、签名比对、三层防竞态），权限协议的执行体全部委托
// 本模块（见 AGENTS.md 提醒目录说明）。
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/notifications/lunio_notification_service.dart';
import '../../../data/repositories/lunio_repository.dart';
import '../../../domain/entities/notification_settings.dart';
import '../../../domain/entities/parking_countdown.dart';

/// 静默目标：一条提醒挂在谁身上——保养项目（按项目 id）或里程更新
/// （按车辆 id）。抑制类偏好 key 由 [ReminderTarget] 加前缀常量在模块
/// 内部拼出，调用方不接触 key 字符串。
sealed class ReminderTarget {
  const ReminderTarget();
}

/// 保养项目目标。
class MaintenanceItemTarget extends ReminderTarget {
  const MaintenanceItemTarget(this.itemId);

  final int itemId;
}

/// 里程更新目标（按车辆）。
class MileageUpdateTarget extends ReminderTarget {
  const MileageUpdateTarget(this.carId);

  final int carId;
}

/// 通知协调器的装配入口。依赖：主容器 [Ref]（读设置 provider、失效
/// 偏好缓存）、[LunioRepository]（偏好读写）、通知服务单例。测试可用
/// 内存数据库 + mock 方法通道直接驱动。
final notificationCoordinatorProvider = Provider<LunioNotificationCoordinator>(
  (ref) {
    return LunioNotificationCoordinator(
      ref: ref,
      repository: ref.watch(lunioRepositoryProvider),
      service: LunioNotificationService.instance,
    );
  },
);

/// 通知协调器。构造依赖全部从外部传入，便于测试替换（字段公开与
/// NotificationSyncController 的 ref 同一风格）。
class LunioNotificationCoordinator {
  LunioNotificationCoordinator({
    required this.ref,
    required this.repository,
    required this.service,
  });

  final Ref ref;
  final LunioRepository repository;
  final LunioNotificationService service;

  // ---- 本模块拥有的偏好 key（写入口唯一）----

  static const _systemNotificationsEnabledKey = 'systemNotificationsEnabled';
  static const _inAppNotificationsEnabledKey = 'inAppNotificationsEnabled';
  static const _maintenanceDueRepeatKey = 'maintenanceDueRepeat';
  static const _systemNotificationPermissionRequestedKey =
      'systemNotificationPermissionRequested';

  // ---- 权限真值协议 ----

  /// 查询系统真实通知开关并回写偏好（用户可能在系统设置里改过）。
  /// 不一致才写库 + 失效偏好缓存；查询失败打日志并回退为偏好当前值
  /// （R14：不静默吞异常）。从不主动弹权限框。
  ///
  /// 返回系统真实开关状态（查询失败时为按偏好推断的值）。
  Future<bool> reconcileSystemEnabled() async {
    final currentValue = await repository.getPreferenceValue(
      _systemNotificationsEnabledKey,
    );
    try {
      final enabled = await service.notificationsEnabled();
      if (currentValue != enabled.toString()) {
        await repository.setPreferenceValue(
          _systemNotificationsEnabledKey,
          enabled.toString(),
        );
        invalidatePreferenceProvidersWithRef(ref);
      }
      return enabled;
    } catch (error) {
      debugPrint(
        'notification_coordinator: 查询系统通知开关失败($error)，回退为偏好当前值',
      );
      return currentValue != 'false';
    }
  }

  /// 请求系统通知权限，并把"已请求过"记入偏好。"是否需要请求"由调用方
  /// 决定（首启链先查"已请求过"偏好，停车保存链每次都请求，与原实现
  /// 一致）。被拒时把系统通知开关偏好写为关并失效缓存，让 UI 立即反映
  /// "系统通知已不可用"。
  ///
  /// 返回是否获得授权。
  Future<bool> requestPermission() async {
    final granted = await service.requestNotificationPermission();
    await repository.setPreferenceValue(
      _systemNotificationPermissionRequestedKey,
      'true',
    );
    if (!granted) {
      await markSystemNotificationsDisabled();
    }
    return granted;
  }

  /// 把系统通知开关偏好写为关并失效缓存（权限被拒 / 系统里被关后的
  /// 统一回写点）。
  Future<void> markSystemNotificationsDisabled() async {
    await repository.setPreferenceValue(
      _systemNotificationsEnabledKey,
      'false',
    );
    invalidatePreferenceProvidersWithRef(ref);
  }

  /// 首启权限链的执行体（原同步控制器 _ensureInitialSystemNotificationPermission
  /// 收编；防重入仍由调用方负责）：
  ///  1. 请求过 → 只把系统真实开关回写偏好（[reconcileSystemEnabled]）；
  ///  2. 没请求过 → 请求并记录授权结果（[requestPermission]）。
  ///
  /// 返回 true 表示本次真的弹了权限请求，调用方应清空系统通知签名并
  /// 立即重跑一轮同步（授权结果影响通知内容）。
  Future<bool> ensureInitialSystemNotificationPermission() async {
    final requested = await repository.getPreferenceValue(
      _systemNotificationPermissionRequestedKey,
    );
    if (requested == 'true') {
      await reconcileSystemEnabled();
      return false;
    }
    await requestPermission();
    return true;
  }

  /// 系统通知调度前的权限协议（原同步控制器 _applySystemNotificationSchedule
  /// 内嵌段收编）：查系统真实开关 → 关着且没请求过权限就补请求 →
  /// 仍不可用则把开关偏好回写为关并取消已排的保养/里程通知（8000/8900 系）。
  ///
  /// 返回 true = 可以继续组装与调度通知。
  Future<bool> ensureSystemNotificationsSchedulable() async {
    var enabled = await service.notificationsEnabled();
    if (!enabled) {
      final requested = await repository.getPreferenceValue(
        _systemNotificationPermissionRequestedKey,
      );
      if (requested != 'true') {
        enabled = await requestPermission();
        if (enabled) {
          return true;
        }
        // 被拒：requestPermission 内部已回写偏好并失效，这里补取消旧通知。
        await service.cancelLunioNotifications();
        return false;
      }
      // 请求过但系统里仍关着：偏好回写为关（与系统真值保持一致）再取消。
      await markSystemNotificationsDisabled();
      await service.cancelLunioNotifications();
      return false;
    }
    return true;
  }

  // ---- 通知设置写入 ----

  /// 保存通知设置：一个事务内批量写 3 个偏好 key（R27）+ 失效偏好缓存。
  /// 保养到期提醒是产品核心能力，设计上不提供关闭入口（R5，原
  /// maintenanceDueEnabled 偏好已移除）。
  Future<void> saveNotificationSettings(
    LunioNotificationSettings settings,
  ) async {
    await repository.updatePreferenceValues({
      _systemNotificationsEnabledKey: settings.systemNotificationsEnabled
          .toString(),
      _inAppNotificationsEnabledKey: settings.inAppNotificationsEnabled
          .toString(),
      _maintenanceDueRepeatKey: settings.dueRepeatFrequency.value,
    });
    invalidatePreferenceProvidersWithRef(ref);
  }

  // ---- 通知清扫协议（数据被整体替换时） ----

  /// 升通知同步代数：作废同步控制器在途任务与"用旧数据排通知"的竞态
  /// （R8）。由下面三个 run* 模板方法在破坏性写库前调用，UI 不再自己
  /// 碰 notificationSyncGenerationProvider。
  void _bumpNotificationSyncGeneration() {
    ref.read(notificationSyncGenerationProvider.notifier).bump();
  }

  /// 删除车辆的收尾模板：升代数作废在途同步 → 执行删库 → 取消保养/里程
  /// 系通知（8000/8900）。R1：删最后一辆车后同步控制器在无车时短路不重排，
  /// 旧调度必须在此显式取消；非最后一辆车的场景取消后会随失效触发的重排
  /// 恢复，代价可忽略。
  ///
  /// [deleteCar] 传入 Repository 的删库动作本身；删库失败（异常）时旧通知
  /// 原样保留（数据未变）并上抛异常。失效车辆类 provider 由调用方负责。
  Future<void> runCarDeletion(Future<void> Function() deleteCar) async {
    _bumpNotificationSyncGeneration();
    await deleteCar();
    await service.cancelLunioNotifications();
  }

  /// 恢复备份的收尾模板：升代数 → 执行恢复 → 取消保养/里程系通知
  /// （8000/8900）。停车 9001/9002 不取消——倒计时偏好保留且仍有效。
  /// 恢复失败（异常，事务已回滚）时旧通知原样保留并上抛异常。
  Future<void> runBackupRestore(Future<void> Function() restoreBackup) async {
    _bumpNotificationSyncGeneration();
    await restoreBackup();
    await service.cancelLunioNotifications();
  }

  /// 清空数据的收尾模板：升代数 → 执行清库（偏好表一并删除，倒计时偏好
  /// 和通知开关都不复存在）→ 取消停车 9001/9002 与保养/里程 8000/8900 系
  /// 残留通知。清库失败（异常）时上抛异常、不取消。
  Future<void> runAllDataClear(Future<void> Function() clearAllData) async {
    _bumpNotificationSyncGeneration();
    await clearAllData();
    await service.cancelParkingCountdownNotification();
    await service.cancelLunioNotifications();
  }

  // ---- 停车倒计时通知 ----

  /// 停车倒计时已保存的通知尾巴（原 UI 内嵌链收编；调用方先写倒计时偏好
  /// 并失效 parkingCountdownProvider 再调用）：
  ///  - 系统通知开关关着 → 到此为止（只保留应用内倒计时）；
  ///  - 开着 → 请求通知权限（顺手记"已请求过"，被拒时
  ///    [requestPermission] 内部回写"系统通知关闭"）→ 授权了再比对同步
  ///    代数 → 申请 Android 精确闹钟 → 调度 9001 到点闹钟 + 9002 常驻通知。
  /// 代数比对（R8）：保存链期间发生恢复备份/清空数据（数据已被整体替换）
  /// 就不再调度，避免排入一条指向已删除状态的通知。
  Future<void> onParkingCountdownSaved(ParkingCountdown countdown) async {
    final syncGeneration = ref.read(notificationSyncGenerationProvider);
    final settings = await ref.read(notificationSettingsProvider.future);
    if (!settings.systemNotificationsEnabled) {
      return;
    }
    final granted = await requestPermission();
    if (!granted) {
      return;
    }
    if (ref.read(notificationSyncGenerationProvider) != syncGeneration) {
      return;
    }
    final exactAlarmGranted = await service.requestExactAlarmPermission();
    await service.scheduleParkingCountdownNotification(
      countdown,
      exactAlarm: exactAlarmGranted,
    );
  }

  /// 停车倒计时已清除的通知收尾（调用方先删偏好并失效
  /// parkingCountdownProvider 再调用）：系统通知开着才取消 9001/9002
  /// （关着时本来就没人调度过）。
  Future<void> onParkingCountdownCleared() async {
    final settings = await ref.read(notificationSettingsProvider.future);
    if (settings.systemNotificationsEnabled) {
      await service.cancelParkingCountdownNotification();
    }
  }

  // ---- 提醒静默协议（"稍后提醒" / "知道了"） ----
  //
  // 两条静默规则（原散在 reminder_notifications / reminder_dialogs /
  // notification_sync_controller 三处，现收进模块，由两个读方法表达）：
  //  - "稍后提醒"：系统通知 + 应用内弹窗一起静默 15 天；
  //  - "知道了"：只静默当天的应用内弹窗，系统通知照发。
  // key 前缀引用 LunioRepository 上的静态常量（单一事实来源）：恢复备份
  // 时按同一组前缀清除抑制记录，两处不会各自漂移。

  /// "稍后提醒"截止日 = 今天 + 15 天（R34：LocalDate 日历加减，不走
  /// 24 小时累加）。
  static LocalDate _snoozeUntilDate(LocalDate today) => today.addDays(15);

  String _maintenanceSnoozeKey(int itemId) =>
      '${LunioRepository.maintenanceReminderSnoozedUntilPrefix}$itemId';

  String _mileageSnoozeKey(int carId) =>
      '${LunioRepository.mileageUpdateSnoozedUntilPrefix}$carId';

  String _maintenanceAcknowledgedKey(int itemId) =>
      '${LunioRepository.maintenanceInAppReminderAcknowledgedOnPrefix}$itemId';

  String _mileageAcknowledgedKey(int carId) =>
      '${LunioRepository.mileageUpdateInAppAcknowledgedOnPrefix}$carId';

  /// 是否处于"稍后提醒"期（截止日 ≥ 今天：截止日当天仍静默，次日恢复）。
  Future<bool> _isSnoozed(String key, LocalDate today) async {
    final value = await repository.getPreferenceValue(key);
    if (value == null) {
      return false;
    }
    final until = LocalDate.tryParse(value);
    if (until == null) {
      return false;
    }
    return until.compareTo(today) >= 0;
  }

  /// 今天是否已点过"知道了"。
  Future<bool> _isAcknowledgedOn(String key, LocalDate today) async {
    final value = await repository.getPreferenceValue(key);
    if (value == null) {
      return false;
    }
    final acknowledgedOn = LocalDate.tryParse(value);
    if (acknowledgedOn == null) {
      return false;
    }
    return acknowledgedOn == today;
  }

  /// 系统通知是否被静默：只有"稍后提醒"会静默系统通知，"知道了"
  /// 不影响系统通知。
  Future<bool> isSilencedForSystemNotification(
    ReminderTarget target,
    LocalDate today,
  ) {
    return switch (target) {
      MaintenanceItemTarget(:final itemId) =>
        _isSnoozed(_maintenanceSnoozeKey(itemId), today),
      MileageUpdateTarget(:final carId) =>
        _isSnoozed(_mileageSnoozeKey(carId), today),
    };
  }

  /// 应用内提醒弹窗是否被静默："稍后提醒"期内，或今天已点过"知道了"。
  Future<bool> isSilencedForInAppDialog(
    ReminderTarget target,
    LocalDate today,
  ) async {
    return switch (target) {
      MaintenanceItemTarget(:final itemId) =>
        await _isSnoozed(_maintenanceSnoozeKey(itemId), today) ||
            await _isAcknowledgedOn(_maintenanceAcknowledgedKey(itemId), today),
      MileageUpdateTarget(:final carId) =>
        await _isSnoozed(_mileageSnoozeKey(carId), today) ||
            await _isAcknowledgedOn(_mileageAcknowledgedKey(carId), today),
    };
  }

  /// 记录"稍后提醒"：逐项写截止日 = 今天 + 15 天（系统通知与应用内
  /// 弹窗一起静默）。
  Future<void> snoozeMaintenanceItems(
    List<int> itemIds,
    LocalDate today,
  ) async {
    final until = _snoozeUntilDate(today).toString();
    for (final itemId in itemIds) {
      await repository.setPreferenceValue(
        _maintenanceSnoozeKey(itemId),
        until,
      );
    }
  }

  /// 记录"稍后提醒"（里程更新按车辆）。
  Future<void> snoozeMileageUpdate(int carId, LocalDate today) async {
    await repository.setPreferenceValue(
      _mileageSnoozeKey(carId),
      _snoozeUntilDate(today).toString(),
    );
  }

  /// 记录"知道了"（保养项目）：写当日 ack 偏好，只静默当天的应用内弹窗。
  Future<void> acknowledgeMaintenanceItem(int itemId, LocalDate today) async {
    await repository.setPreferenceValue(
      _maintenanceAcknowledgedKey(itemId),
      today.toString(),
    );
  }

  /// 记录"知道了"（里程更新按车辆）。
  Future<void> acknowledgeMileageUpdate(int carId, LocalDate today) async {
    await repository.setPreferenceValue(
      _mileageAcknowledgedKey(carId),
      today.toString(),
    );
  }
}

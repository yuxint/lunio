// 应用内提醒弹窗链路的决策体：'哪些到期提醒要弹应用内弹窗、弹窗动作
// （知道了/稍后提醒）各写哪些抑制偏好、动作后什么时候要强制重排系统
// 通知'这一组决策的 plain-Dart 模块（2026-10-15 收编）。
//
// 在 App 中的位置：NotificationSyncController._showDueInAppNotifications
// 的执行内核。控制器保留被动监听外壳（签名比对、GuardedOp 防重入、
// _disposed、shellContext 提取），本类持有检查链的全部决策；静默读取、
// 弹窗呈现、抑制偏好写、强制重排全部经构造注入的接缝传入，本类不持有
// WidgetRef/BuildContext，可无 widget 单测（单测
// test/features/reminder_dialog_flow_test.dart，completer 驱动 await
// 边界 + 真守卫插旗演练中间态）。这是 reminders 域最后一个收编的 UI
// 融合决策体，接法同 RecordFormController/CarFormController/
// FuelTierListController 先例（plain-Dart 控制器 + 注入 UI 实现）。
// ≈ Java Web 里从 Controller 抽出来的应用服务：输入是快照数据，副作用
// 全部走接口，测试注入假实现即可在确定性时序下演练每个 await 边界。
//
// 与守卫的边界：同步守卫（同步代数 + 写库中间态旗）的领票与检查点语义
// 仍归 notification_sync_guard.dart，本类只在不可逆副作用（弹窗、写
// 抑制偏好、触发重排）前经 [InAppReminderDialogFlow.acquireRun] 领票问
// isValid，不拥有任何守卫状态。
import '../../../core/date/local_date.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/notification_settings.dart';
import 'notification_coordinator.dart';
import 'notification_sync_guard.dart';
import 'reminder_notifications.dart';
import 'reminder_rows.dart';

/// 弹窗动作结果枚举：应用内提醒弹窗（reminder_dialogs.dart）的返回值，
/// 也是本决策体处理抑制偏好写与强制重排的分支依据。原定义在
/// reminder_dialogs.dart，2026-10-15 随决策体收编迁入本文件——决策体
/// 不 import material 文件，弹窗 UI 反向消费这里的枚举。
enum ReminderDialogAction { acknowledged, snoozed }

/// 保养提醒弹窗呈现接缝：签名对齐 reminder_dialogs.dart 的
/// showMaintenanceReminderDialog（context/coordinator 由生产闭包组装）。
/// 返回 null = 点遮罩/返回键关闭（无动作）。
typedef ShowMaintenanceReminderDialog = Future<ReminderDialogAction?> Function({
  required Car car,
  required List<ReminderViewData> maintenanceNotices,
  required LocalDate today,
});

/// 里程更新弹窗呈现接缝：签名对齐 showMileageUpdateReminderDialog。
typedef ShowMileageUpdateReminderDialog
    = Future<ReminderDialogAction?> Function({
  required Car car,
  required LocalDate today,
});

/// 应用内提醒弹窗链路的决策体（plain-Dart，≈ 表单域 RecordFormController
/// 的通知域对应物）。一次构造注入全部接缝，实例无状态、可复用。
class InAppReminderDialogFlow {
  const InAppReminderDialogFlow({
    required this.acquireRun,
    required this.isSilencedForInAppDialog,
    required this.canPresentDialog,
    required this.showMaintenanceDialog,
    required this.showMileageDialog,
    required this.acknowledgeMaintenanceItem,
    required this.acknowledgeMileageUpdate,
    required this.onForceReschedule,
  });

  /// 领一张同步票（生产 = 守卫 provider 的 acquire(isDisposed:)；测试
  /// 注入真守卫 + ProviderContainer，中间态经 guard.begin/settle 演练）。
  /// 领票与检查点语义归守卫模块，本类只问票不拥有协议。
  final SyncRun Function() acquireRun;

  /// 静默判定读取（"稍后提醒"期内，或今天已点过"知道了"）：生产绑定
  /// 通知协调器 isSilencedForInAppDialog；测试经 completer 控制 await
  /// 边界（在静默读挂起期间插入写库中间态，演练循环内检查点）。
  final Future<bool> Function(ReminderTarget target, LocalDate today)
      isSilencedForInAppDialog;

  /// 弹窗能否立即展示（生产 = 主壳层 context 的 null/mounted 检查）。
  /// false = 壳层已拆，放弃整轮（等下一轮补判）——与控制器原实现的
  /// shellContext 检查同语义，本类不碰 BuildContext。
  final bool Function() canPresentDialog;

  /// 保养提醒弹窗呈现（传入已过滤的生效到期清单，返回用户动作）。
  /// "15 天内不再提醒"的 snooze 偏好写在呈现闭包内部完成（弹窗骨架的
  /// saving 语义要求 snooze 写完才 pop），不经本类。
  final ShowMaintenanceReminderDialog showMaintenanceDialog;

  /// 里程更新弹窗呈现。
  final ShowMileageUpdateReminderDialog showMileageDialog;

  /// "知道了"当日 ack 偏好写（生产绑定协调器同名单方法）。
  final Future<void> Function(int itemId, LocalDate today)
      acknowledgeMaintenanceItem;

  /// "知道了"当日 ack 偏好写（里程更新按车辆）。
  final Future<void> Function(int carId, LocalDate today)
      acknowledgeMileageUpdate;

  /// 动作后的强制重排（生产 = 清空系统通知与应用内两个签名并立即重跑
  /// syncFromProviders；_disposed 检查在生产闭包内）。snooze 影响系统
  /// 通知内容、ack 影响应用内弹窗静默，两类动作都触发重排。
  final void Function() onForceReschedule;

  /// 应用内提醒检查链：静默过滤 → 无到期短路 → 依次呈现两类弹窗并按
  /// 动作写抑制偏好 → 动作后强制重排。调用方（通知同步控制器）已在外层
  /// 做签名比对与 GuardedOp 防重入；本方法内部的检查点全部经同步票。
  ///
  /// 参数是通知同步控制器从应用车辆数据束与通知设置快照出的当轮数据
  /// （车/项目/记录/生效今天 + 通知设置），本方法不读 provider。
  Future<void> checkAndPresent({
    required LunioNotificationSettings settings,
    required Car car,
    required List<MaintenanceItem> items,
    required List<MaintenanceRecord> records,
    required LocalDate today,
  }) async {
    final run = acquireRun();
    // 入口复查：写库进行中读到的 items/records 是未提交的半成品，算都
    // 不要算（控制器 syncFromProviders 入口早退只挡"检查开始时写库已在
    // 跑"的那一半，这里挡"检查开始后写库才开始"的另一半）。
    if (!run.isValid) {
      return;
    }
    if (!settings.inAppNotificationsEnabled) {
      return;
    }
    // 生效到期清单（GLOSSARY 词条）：到期项目经静默判定逐个过滤（判定
    // 是 await——期间可能发生破坏性写库，每轮循环后问一次票，假了整轮
    // 放弃）。
    final dueNotices = <ReminderViewData>[];
    for (final notice in maintenanceNotices(
      car: car,
      items: items,
      records: records,
      today: today,
    )) {
      final itemId = notice.item.id;
      if (itemId == null) {
        continue;
      }
      if (!await isSilencedForInAppDialog(
        MaintenanceItemTarget(itemId),
        today,
      )) {
        dueNotices.add(notice);
      }
      if (!run.isValid) {
        return;
      }
    }
    final showMileageReminder =
        car.id != null &&
        mileageUpdateReminderDue(car: car, records: records, today: today) &&
        !await isSilencedForInAppDialog(
          MileageUpdateTarget(car.id!),
          today,
        );
    if (dueNotices.isEmpty && !showMileageReminder) {
      return;
    }
    // 展示前复查第一道（保养弹窗，与下方展示调用之间无 await，无竞态
    // 窗口）：旗真 = 写库仍在进行，清单是半成品；代数变了 = 写库在本次
    // 检查期间已开始并结束，数据过期；disposed = 壳层已拆。都放弃，
    // 等最终一轮补判。
    if (!run.isValid) {
      return;
    }
    var changedSystemSchedule = false;
    if (dueNotices.isNotEmpty) {
      if (!canPresentDialog()) {
        return;
      }
      final action = await showMaintenanceDialog(
        car: car,
        maintenanceNotices: dueNotices,
        today: today,
      );
      if (!run.isValid) {
        return;
      }
      if (action != null) {
        // snoozed 与 acknowledged 都改变抑制状态 → 都要重排；snooze 的
        // 偏好写已在弹窗呈现闭包内完成，这里只剩 acknowledged 的当日
        // ack 写（逐项，经协调器接缝）。
        changedSystemSchedule = true;
        if (action == ReminderDialogAction.acknowledged) {
          for (final notice in dueNotices) {
            final itemId = notice.item.id;
            if (itemId != null) {
              await acknowledgeMaintenanceItem(itemId, today);
            }
          }
        }
      }
    }
    if (showMileageReminder) {
      if (!canPresentDialog()) {
        return;
      }
      // 展示前复查第二道（里程弹窗，与下方展示调用之间无 await）：保养
      // 弹窗挂起与 ack 写偏好都是 await，破坏性写库可能在期间开始并
      // 结束，showMileageReminder 是旧快照算出来的，弹前必须再问一次票
      // （2026-09-25 补齐，审查：此前只有保养弹窗前一道）。
      if (!run.isValid) {
        return;
      }
      final action = await showMileageDialog(car: car, today: today);
      if (!run.isValid) {
        return;
      }
      if (action != null) {
        changedSystemSchedule = true;
        final carId = car.id;
        if (action == ReminderDialogAction.acknowledged && carId != null) {
          await acknowledgeMileageUpdate(carId, today);
        }
      }
    }
    if (changedSystemSchedule) {
      onForceReschedule();
    }
  }
}

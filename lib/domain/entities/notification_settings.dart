// 通知设置实体 + 重复频率枚举（≈ Java 的配置 DTO 与枚举类）。
//
// 这三个值持久化在 app_preferences 表的 3 个 key 里
// （systemNotificationsEnabled / inAppNotificationsEnabled /
//   maintenanceDueRepeat），
// 由 notificationSettingsProvider 一次性读出组装成本对象。
//
// 产品口径：保养到期提醒是 App 的核心能力，设计上不提供用户关闭入口
// （原 maintenanceDueEnabled 偏好已于 2026-08-29 移除，见审查报告 R5）。
//
// "extension on 枚举"是 Dart 特性：给已有枚举追加方法/静态工厂，
// Java 对照：枚举里写字段方法，或用工具类。Codec 后缀即编解码器。
enum ReminderRepeatFrequency {
  daily,
  weekly,
  everyTwoWeeks,
  everyThreeWeeks,
  monthly,
}

class LunioNotificationSettings {
  const LunioNotificationSettings({
    this.systemNotificationsEnabled = true,
    this.inAppNotificationsEnabled = true,
    this.dueRepeatFrequency = ReminderRepeatFrequency.weekly,
  });

  /// 系统通知总开关（对应 OS 通知权限 + 应用偏好，两者同时满足才发通知）。
  final bool systemNotificationsEnabled;

  /// 应用内提醒弹窗开关（到期时在 App 前台弹卡片）。
  final bool inAppNotificationsEnabled;

  /// 到期后的重复提醒频率（提醒被忽略后隔多久再提醒一次）。
  final ReminderRepeatFrequency dueRepeatFrequency;

  /// 复制并替换部分字段。
  LunioNotificationSettings copyWith({
    bool? systemNotificationsEnabled,
    bool? inAppNotificationsEnabled,
    ReminderRepeatFrequency? dueRepeatFrequency,
  }) {
    return LunioNotificationSettings(
      systemNotificationsEnabled:
          systemNotificationsEnabled ?? this.systemNotificationsEnabled,
      inAppNotificationsEnabled:
          inAppNotificationsEnabled ?? this.inAppNotificationsEnabled,
      dueRepeatFrequency: dueRepeatFrequency ?? this.dueRepeatFrequency,
    );
  }
}

/// 重复频率的持久化编解码 + 中文文案。
extension ReminderRepeatFrequencyCodec on ReminderRepeatFrequency {
  /// 持久化到偏好表的字符串值。
  String get value {
    return switch (this) {
      ReminderRepeatFrequency.daily => 'daily',
      ReminderRepeatFrequency.weekly => 'weekly',
      ReminderRepeatFrequency.everyTwoWeeks => 'everyTwoWeeks',
      ReminderRepeatFrequency.everyThreeWeeks => 'everyThreeWeeks',
      ReminderRepeatFrequency.monthly => 'monthly',
    };
  }

  /// UI 展示文案。
  String get label {
    return switch (this) {
      ReminderRepeatFrequency.daily => '每天',
      ReminderRepeatFrequency.weekly => '每周',
      ReminderRepeatFrequency.everyTwoWeeks => '每 2 周',
      ReminderRepeatFrequency.everyThreeWeeks => '每 3 周',
      ReminderRepeatFrequency.monthly => '每月',
    };
  }

  /// 从偏好值解析；null/未知值（含 daily）一律回退 weekly——
  /// 通知设置 UI 只提供周/双周/月三档，daily 仅内部使用。
  static ReminderRepeatFrequency parse(String? value) {
    return switch (value) {
      'weekly' => ReminderRepeatFrequency.weekly,
      'everyTwoWeeks' => ReminderRepeatFrequency.everyTwoWeeks,
      'everyThreeWeeks' => ReminderRepeatFrequency.everyThreeWeeks,
      'monthly' => ReminderRepeatFrequency.monthly,
      _ => ReminderRepeatFrequency.weekly,
    };
  }
}

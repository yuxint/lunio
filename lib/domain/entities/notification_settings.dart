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
    this.maintenanceDueEnabled = true,
    this.dueRepeatFrequency = ReminderRepeatFrequency.weekly,
  });

  final bool systemNotificationsEnabled;
  final bool inAppNotificationsEnabled;
  final bool maintenanceDueEnabled;
  final ReminderRepeatFrequency dueRepeatFrequency;

  LunioNotificationSettings copyWith({
    bool? systemNotificationsEnabled,
    bool? inAppNotificationsEnabled,
    bool? maintenanceDueEnabled,
    ReminderRepeatFrequency? dueRepeatFrequency,
  }) {
    return LunioNotificationSettings(
      systemNotificationsEnabled:
          systemNotificationsEnabled ?? this.systemNotificationsEnabled,
      inAppNotificationsEnabled:
          inAppNotificationsEnabled ?? this.inAppNotificationsEnabled,
      maintenanceDueEnabled:
          maintenanceDueEnabled ?? this.maintenanceDueEnabled,
      dueRepeatFrequency: dueRepeatFrequency ?? this.dueRepeatFrequency,
    );
  }
}

extension ReminderRepeatFrequencyCodec on ReminderRepeatFrequency {
  String get value {
    return switch (this) {
      ReminderRepeatFrequency.daily => 'daily',
      ReminderRepeatFrequency.weekly => 'weekly',
      ReminderRepeatFrequency.everyTwoWeeks => 'everyTwoWeeks',
      ReminderRepeatFrequency.everyThreeWeeks => 'everyThreeWeeks',
      ReminderRepeatFrequency.monthly => 'monthly',
    };
  }

  String get label {
    return switch (this) {
      ReminderRepeatFrequency.daily => '每天',
      ReminderRepeatFrequency.weekly => '每周',
      ReminderRepeatFrequency.everyTwoWeeks => '每 2 周',
      ReminderRepeatFrequency.everyThreeWeeks => '每 3 周',
      ReminderRepeatFrequency.monthly => '每月',
    };
  }

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

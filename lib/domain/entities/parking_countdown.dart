// 停车倒计时实体：一次"停车计时"的全部状态。
//
// 这是临时状态（不是业务数据）：以 JSON 形式存在 app_preferences 表的
// `parkingCountdown` key 下，**不进入** JSON 备份（备份契约见 backup_codec.dart）。
// 开始（保存）/结束（清除）由提醒页停车倒计时卡片触发。
//
// 用真实系统时间（而非手动日期）计算剩余时间——即使开发者模式的
// 手动日期生效，倒计时依然走真实时钟。
class ParkingCountdown {
  /// 构造时校验时长必须为正数（分钟换算成秒）。
  ParkingCountdown({required this.startedAt, required this.durationSeconds}) {
    if (durationSeconds <= 0) {
      throw ArgumentError.value(
        durationSeconds,
        'durationSeconds',
        'must be positive',
      );
    }
  }

  /// 从偏好表里存的 JSON 反序列化（factory 构造函数 ≈ 静态工厂方法）。
  factory ParkingCountdown.fromJson(Map<String, Object?> json) {
    return ParkingCountdown(
      startedAt: DateTime.parse(json['startedAt'] as String),
      durationSeconds: json['durationSeconds'] as int,
    );
  }

  /// 入场时间（用户在时间选择器里选的时刻，本地时区）。
  final DateTime startedAt;

  /// 免费停车总时长（秒）。
  final int durationSeconds;

  /// 到期时刻 = 入场时间 + 总时长。getter ≈ Java 的 getEndsAt() 计算属性。
  DateTime get endsAt => startedAt.add(Duration(seconds: durationSeconds));

  /// 序列化为 JSON 存偏好表。
  Map<String, Object?> toJson() {
    return {
      'startedAt': startedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
    };
  }

  // Dart 默认用"对象身份"比较相等（≈ Java 的 ==，比引用）。
  // 重写 operator== / hashCode 后变成"值相等"（≈ Lombok @EqualsAndHashCode），
  // 用于 provider 签名比较判断"倒计时是否变化、是否需要重排系统通知"。
  @override
  bool operator ==(Object other) {
    return other is ParkingCountdown &&
        other.startedAt == startedAt &&
        other.durationSeconds == durationSeconds;
  }

  @override
  int get hashCode => Object.hash(startedAt, durationSeconds);
}

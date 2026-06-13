class ParkingCountdown {
  ParkingCountdown({required this.startedAt, required this.durationSeconds}) {
    if (durationSeconds <= 0) {
      throw ArgumentError.value(
        durationSeconds,
        'durationSeconds',
        'must be positive',
      );
    }
  }

  factory ParkingCountdown.fromJson(Map<String, Object?> json) {
    return ParkingCountdown(
      startedAt: DateTime.parse(json['startedAt'] as String),
      durationSeconds: json['durationSeconds'] as int,
    );
  }

  final DateTime startedAt;
  final int durationSeconds;

  DateTime get endsAt => startedAt.add(Duration(seconds: durationSeconds));

  Map<String, Object?> toJson() {
    return {
      'startedAt': startedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ParkingCountdown &&
        other.startedAt == startedAt &&
        other.durationSeconds == durationSeconds;
  }

  @override
  int get hashCode => Object.hash(startedAt, durationSeconds);
}

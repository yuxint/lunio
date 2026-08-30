// 本地日期值对象：只含年月日（≈ Java 的 java.time.LocalDate 简化版）。
//
// 全项目的业务日期统一用它：上路日期、记录日期、手动日期、提醒基线。
// 序列化格式固定 yyyy-MM-dd（数据库文本列、备份 JSON 都是字符串）。
//
// 不可变 + 值相等（重写了 == / hashCode），可直接放进 Set/Map key。
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  /// 从 DateTime 截取年月日（丢弃时分秒）。
  factory LocalDate.fromDateTime(DateTime dateTime) {
    return LocalDate(dateTime.year, dateTime.month, dateTime.day);
  }

  /// 严格解析 yyyy-MM-dd：先用正则卡格式，再用 DateTime 归一化反查
  /// （防住 2026-02-30 这种"格式对但日期不存在"的值）。
  /// 非法输入抛 FormatException（≈ Java 的 DateTimeParseException）。
  factory LocalDate.parse(String value) {
    final pattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!pattern.hasMatch(value)) {
      throw FormatException('Invalid date format', value);
    }
    final parts = value.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    final normalized = DateTime(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw FormatException('Invalid date format', value);
    }
    return LocalDate(year, month, day);
  }

  /// 宽松解析：失败返回 null 而不是抛错（读偏好等不可信来源时用）。
  static LocalDate? tryParse(String value) {
    try {
      return LocalDate.parse(value);
    } on FormatException {
      return null;
    }
  }

  final int year;
  final int month;
  final int day;

  /// 转 DateTime（当日 00:00，本地时区）。用于天数差值计算。
  DateTime toDateTime() => DateTime(year, month, day);

  /// 加 n 天（可为负）：走 DateTime 归一化（跨月/跨年自动进位），
  /// 与 Java 的 LocalDate.plusDays 行为一致。纯日历加减，不做 24 小时
  /// 累加（R34：小时数累加在夏令时切换日会漂移墙钟时刻）。
  LocalDate addDays(int days) {
    final normalized = DateTime(year, month, day + days);
    return LocalDate(normalized.year, normalized.month, normalized.day);
  }

  /// 加 n 个月，月末自动钳制：1.31 + 1月 → 2.28/2.29（与 Java 的
  /// LocalDate.plusMonths 行为一致）。时间进度计算的到期日靠它保证正确。
  LocalDate addMonths(int months) {
    final targetMonthIndex = month - 1 + months;
    final targetYear = year + targetMonthIndex ~/ 12;
    final targetMonth = targetMonthIndex % 12 + 1;
    final targetDay = day.clamp(1, _daysInMonth(targetYear, targetMonth));
    return LocalDate(targetYear, targetMonth, targetDay);
  }

  /// 距另一个日期的整月数（不足整月按日扣减：3.15 → 4.10 = 0 个月）。
  int monthsUntil(LocalDate other) {
    var months = (other.year - year) * 12 + other.month - month;
    if (other.day < day) {
      months -= 1;
    }
    return months;
  }

  /// 距另一个日期的天数（other 在后为正）。
  /// ⚠ 用本地午夜差 inDays：跨夏令时的天数会差 1（目标市场无 DST，影响小）。
  int daysUntil(LocalDate other) {
    return other.toDateTime().difference(toDateTime()).inDays;
  }

  /// 比较先后（字符串比较，因 yyyy-MM-dd 零填充，字典序=时间序）。
  @override
  int compareTo(LocalDate other) {
    return toString().compareTo(other.toString());
  }

  /// 输出 yyyy-MM-dd（数据库与备份的存储格式）。
  @override
  String toString() {
    final paddedMonth = month.toString().padLeft(2, '0');
    final paddedDay = day.toString().padLeft(2, '0');
    return '$year-$paddedMonth-$paddedDay';
  }

  @override
  bool operator ==(Object other) {
    return other is LocalDate &&
        year == other.year &&
        month == other.month &&
        day == other.day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// 某年某月天数：DateTime(year, month+1, 0) 即"下月第 0 天"= 本月最后一天。
int _daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

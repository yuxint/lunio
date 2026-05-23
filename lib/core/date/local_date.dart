class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  factory LocalDate.fromDateTime(DateTime dateTime) {
    return LocalDate(dateTime.year, dateTime.month, dateTime.day);
  }

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

  final int year;
  final int month;
  final int day;

  DateTime toDateTime() => DateTime(year, month, day);

  LocalDate addMonths(int months) {
    final targetMonthIndex = month - 1 + months;
    final targetYear = year + targetMonthIndex ~/ 12;
    final targetMonth = targetMonthIndex % 12 + 1;
    final targetDay = day.clamp(1, _daysInMonth(targetYear, targetMonth));
    return LocalDate(targetYear, targetMonth, targetDay);
  }

  int monthsUntil(LocalDate other) {
    var months = (other.year - year) * 12 + other.month - month;
    if (other.day < day) {
      months -= 1;
    }
    return months;
  }

  int daysUntil(LocalDate other) {
    return other.toDateTime().difference(toDateTime()).inDays;
  }

  @override
  int compareTo(LocalDate other) {
    return toString().compareTo(other.toString());
  }

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

int _daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

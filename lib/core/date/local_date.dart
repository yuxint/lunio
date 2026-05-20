class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  factory LocalDate.fromDateTime(DateTime dateTime) {
    return LocalDate(dateTime.year, dateTime.month, dateTime.day);
  }

  factory LocalDate.parse(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      throw FormatException('Invalid date format', value);
    }
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    final date = LocalDate(year, month, day);
    if (date.toString() != value) {
      throw FormatException('Invalid date format', value);
    }
    return date;
  }

  final int year;
  final int month;
  final int day;

  DateTime toDateTime() => DateTime(year, month, day);

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

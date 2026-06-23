// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_default_maintenance_item.dart';

int notificationSyncGeneration = 0;

class FilterBar extends StatelessWidget {
  const FilterBar({
    required this.labels,
    required this.selectedIndexes,
    required this.onSelected,
  });

  final List<String> labels;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Builder(
              builder: (context) {
                final selected = selectedIndexes.contains(index);
                return InkWell(
                  onTap: () => onSelected(index),
                  borderRadius: BorderRadius.circular(12),
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? tokens.primarySoft : tokens.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? tokens.primary.withValues(alpha: 0.34)
                                : tokens.line,
                          ),
                        ),
                        child: Text(
                          labels[index],
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: selected ? tokens.primary : tokens.ink,
                              ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: tokens.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: tokens.surface,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (index != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class ItemPills extends StatelessWidget {
  const ItemPills({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: tokens.ink,
      fontWeight: FontWeight.w700,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = _packedPillRows(
          labels: labels,
          maxWidth: constraints.maxWidth,
          textStyle: textStyle,
          textScaler: textScaler,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (
                    var itemIndex = 0;
                    itemIndex < rows[rowIndex].length;
                    itemIndex++
                  ) ...[
                    if (itemIndex > 0) const SizedBox(width: 6),
                    SizedBox(
                      width: rows[rowIndex][itemIndex].width,
                      child: ItemPill(
                        label: rows[rowIndex][itemIndex].label,
                        style: textStyle,
                      ),
                    ),
                  ],
                ],
              ),
              if (rowIndex < rows.length - 1) const SizedBox(height: 6),
            ],
          ],
        );
      },
    );
  }
}

class ItemPill extends StatelessWidget {
  const ItemPill({required this.label, required this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.line.withValues(alpha: 0.72)),
      ),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

class _PackedPill {
  const _PackedPill({required this.label, required this.width});

  final String label;
  final double width;
}

List<List<_PackedPill>> _packedPillRows({
  required List<String> labels,
  required double maxWidth,
  required TextStyle? textStyle,
  required TextScaler textScaler,
}) {
  if (labels.isEmpty) {
    return const [];
  }
  if (!maxWidth.isFinite || maxWidth <= 0) {
    return [
      labels.map((label) => _PackedPill(label: label, width: 0)).toList(),
    ];
  }
  const spacing = 6.0;
  const horizontalPadding = 18.0;
  const measurementSlack = 4.0;
  const minPillWidth = 58.0;
  final remaining = labels
      .map(
        (label) => _PackedPill(
          label: label,
          width:
              (_measureTextWidth(label, textStyle, textScaler) +
                      horizontalPadding +
                      measurementSlack)
                  .clamp(minPillWidth, maxWidth),
        ),
      )
      .toList();
  final rows = <List<_PackedPill>>[];
  while (remaining.isNotEmpty) {
    final row = <_PackedPill>[];
    var usedWidth = 0.0;
    while (remaining.isNotEmpty) {
      var selectedIndex = -1;
      for (var index = 0; index < remaining.length; index++) {
        final extraSpacing = row.isEmpty ? 0.0 : spacing;
        if (usedWidth + extraSpacing + remaining[index].width <= maxWidth) {
          selectedIndex = index;
          break;
        }
      }
      if (selectedIndex == -1) {
        if (row.isEmpty) {
          selectedIndex = 0;
        } else {
          break;
        }
      }
      final item = remaining.removeAt(selectedIndex);
      usedWidth += (row.isEmpty ? 0.0 : spacing) + item.width;
      row.add(item);
    }
    rows.add(row);
  }
  return rows;
}

double _measureTextWidth(String text, TextStyle? style, TextScaler textScaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  return painter.width;
}

class SmallActionButton extends StatelessWidget {
  const SmallActionButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.primary = false,
    this.secondary = false,
    this.muted = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool primary;
  final bool secondary;
  final bool muted;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final backgroundColor = danger
        ? tokens.dangerSoft
        : primary
        ? tokens.primarySoft
        : secondary
        ? tokens.secondarySoft
        : muted
        ? tokens.surface3
        : tokens.surface2;
    final foregroundColor = onPressed == null
        ? tokens.subtle
        : danger
        ? tokens.danger
        : primary
        ? tokens.primary
        : secondary
        ? tokens.secondary
        : muted
        ? tokens.muted
        : tokens.ink;
    return SizedBox(
      height: 34,
      child: Tooltip(
        message: tooltip ?? label,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class PrototypeSheetFrame extends StatelessWidget {
  const PrototypeSheetFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.bottomInset = 0,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: tokens.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
    final sheet = Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.18),
            blurRadius: 54,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: SingleChildScrollView(child: content),
    );
    return sheet;
  }
}

class ChoiceChipButton extends StatelessWidget {
  const ChoiceChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.primarySoft : tokens.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? tokens.primary.withValues(alpha: 0.3)
                : tokens.line,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? tokens.primary : tokens.ink,
          ),
        ),
      ),
    );
  }
}

Future<LocalDate?> showSimpleDatePicker(
  BuildContext context, {
  required LocalDate initialDate,
  required LocalDate firstDate,
  required LocalDate lastDate,
  LocalDate? today,
}) {
  return showLunioModalSheet<LocalDate>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: SimpleDatePicker(
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
          today: today ?? LocalDate.fromDateTime(DateTime.now()),
        ),
      ),
    ),
  );
}

class SimpleDatePicker extends StatefulWidget {
  const SimpleDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.today,
  });

  final LocalDate initialDate;
  final LocalDate firstDate;
  final LocalDate lastDate;
  final LocalDate today;

  @override
  State<SimpleDatePicker> createState() => SimpleDatePickerState();
}

class SimpleDatePickerState extends State<SimpleDatePicker> {
  late LocalDate selectedDate;
  late int visibleYear;
  late int visibleMonth;
  late int visibleYearPageStart;
  _DatePickerMode mode = _DatePickerMode.day;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate;
    visibleYear = selectedDate.year;
    visibleMonth = selectedDate.month;
    visibleYearPageStart = _yearPageStartFor(visibleYear);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return LunioSheetScaffold(
      title: '选择日期',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DatePickerHeader(
            mode: mode,
            visibleYear: visibleYear,
            visibleMonth: visibleMonth,
            yearPageStart: visibleYearPageStart,
            canGoPrevious: _canGoPrevious(),
            canGoNext: _canGoNext(),
            onPrevious: _goPrevious,
            onNext: _goNext,
            onYearTap: () => setState(() {
              visibleYearPageStart = _yearPageStartFor(visibleYear);
              mode = _DatePickerMode.year;
            }),
            onMonthTap: () => setState(() => mode = _DatePickerMode.month),
          ),
          if (_todayInRange()) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _selectToday,
                icon: const Icon(Icons.today_outlined, size: 18),
                label: const Text('今天'),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.primary,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: switch (mode) {
              _DatePickerMode.day => _buildDayGrid(context),
              _DatePickerMode.month => _buildMonthGrid(context),
              _DatePickerMode.year => _buildYearGrid(context),
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LunioSecondaryButton(
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LunioPrimaryButton(
                  label: '确定',
                  onPressed: () => Navigator.of(context).pop(selectedDate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayGrid(BuildContext context) {
    final firstWeekday = DateTime(visibleYear, visibleMonth, 1).weekday;
    final daysInMonth = DateTime(visibleYear, visibleMonth + 1, 0).day;
    final leadingBlankCount = firstWeekday - 1;
    final cells = leadingBlankCount + daysInMonth;
    final totalCells = ((cells + 6) ~/ 7) * 7;
    return Column(
      key: const ValueKey(_DatePickerMode.day),
      children: [
        Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                  SizedBox(
                    height: 20,
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
            for (var row = 0; row < totalCells ~/ 7; row++)
              TableRow(
                children: [
                  for (var column = 0; column < 7; column++)
                    Padding(
                      padding: EdgeInsets.only(
                        top: row == 0 ? 0 : 6,
                        left: column == 0 ? 0 : 3,
                        right: column == 6 ? 0 : 3,
                      ),
                      child: _dateCellForIndex(
                        row * 7 + column,
                        leadingBlankCount,
                        daysInMonth,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _dateCellForIndex(int index, int leadingBlankCount, int daysInMonth) {
    if (index < leadingBlankCount || index >= leadingBlankCount + daysInMonth) {
      return const SizedBox(height: 42);
    }
    return SizedBox(
      height: 42,
      child: DateCell(
        date: LocalDate(
          visibleYear,
          visibleMonth,
          index - leadingBlankCount + 1,
        ),
        selectedDate: selectedDate,
        firstDate: widget.firstDate,
        lastDate: widget.lastDate,
        onSelected: (date) => setState(() => selectedDate = date),
      ),
    );
  }

  Widget _buildMonthGrid(BuildContext context) {
    return DateOptionTable(
      key: const ValueKey(_DatePickerMode.month),
      children: [
        for (var month = 1; month <= 12; month++)
          DateOptionCell(
            label: '$month月',
            selected:
                visibleYear == selectedDate.year && month == selectedDate.month,
            enabled: _monthEnabled(visibleYear, month),
            onTap: () => _selectMonth(month),
          ),
      ],
    );
  }

  Widget _buildYearGrid(BuildContext context) {
    return DateOptionTable(
      key: const ValueKey(_DatePickerMode.year),
      children: [
        for (var offset = 0; offset < 12; offset++)
          DateOptionCell(
            label: '${visibleYearPageStart + offset}年',
            selected: visibleYearPageStart + offset == visibleYear,
            enabled: _yearEnabled(visibleYearPageStart + offset),
            onTap: () => _selectYear(visibleYearPageStart + offset),
          ),
      ],
    );
  }

  bool _canGoPrevious() {
    return switch (mode) {
      _DatePickerMode.day =>
        visibleYear > widget.firstDate.year ||
            (visibleYear == widget.firstDate.year &&
                visibleMonth > widget.firstDate.month),
      _DatePickerMode.month => visibleYear > widget.firstDate.year,
      _DatePickerMode.year => visibleYearPageStart > widget.firstDate.year,
    };
  }

  bool _canGoNext() {
    return switch (mode) {
      _DatePickerMode.day =>
        visibleYear < widget.lastDate.year ||
            (visibleYear == widget.lastDate.year &&
                visibleMonth < widget.lastDate.month),
      _DatePickerMode.month => visibleYear < widget.lastDate.year,
      _DatePickerMode.year => visibleYearPageStart + 11 < widget.lastDate.year,
    };
  }

  void _goPrevious() {
    setState(() {
      switch (mode) {
        case _DatePickerMode.day:
          _moveMonth(-1);
        case _DatePickerMode.month:
          visibleYear -= 1;
          _clampVisibleMonth();
          selectedDate = _dateForVisibleMonth(selectedDate.day);
        case _DatePickerMode.year:
          visibleYearPageStart -= 12;
      }
    });
  }

  void _goNext() {
    setState(() {
      switch (mode) {
        case _DatePickerMode.day:
          _moveMonth(1);
        case _DatePickerMode.month:
          visibleYear += 1;
          _clampVisibleMonth();
          selectedDate = _dateForVisibleMonth(selectedDate.day);
        case _DatePickerMode.year:
          visibleYearPageStart += 12;
      }
    });
  }

  void _moveMonth(int delta) {
    visibleMonth += delta;
    if (visibleMonth < 1) {
      visibleYear -= 1;
      visibleMonth = 12;
    }
    if (visibleMonth > 12) {
      visibleYear += 1;
      visibleMonth = 1;
    }
    selectedDate = _dateForVisibleMonth(selectedDate.day);
  }

  void _selectYear(int year) {
    setState(() {
      visibleYear = year;
      _clampVisibleMonth();
      selectedDate = _dateForVisibleMonth(selectedDate.day);
      mode = _DatePickerMode.month;
    });
  }

  void _selectMonth(int month) {
    setState(() {
      visibleMonth = month;
      selectedDate = _dateForVisibleMonth(selectedDate.day);
      mode = _DatePickerMode.day;
    });
  }

  void _selectToday() {
    final today = widget.today;
    setState(() {
      selectedDate = today;
      visibleYear = today.year;
      visibleMonth = today.month;
      visibleYearPageStart = _yearPageStartFor(today.year);
      mode = _DatePickerMode.day;
    });
  }

  void _clampVisibleMonth() {
    final firstMonth = visibleYear == widget.firstDate.year
        ? widget.firstDate.month
        : 1;
    final lastMonth = visibleYear == widget.lastDate.year
        ? widget.lastDate.month
        : 12;
    visibleMonth = visibleMonth.clamp(firstMonth, lastMonth);
  }

  LocalDate _dateForVisibleMonth(int preferredDay) {
    final daysInMonth = DateTime(visibleYear, visibleMonth + 1, 0).day;
    var date = LocalDate(
      visibleYear,
      visibleMonth,
      preferredDay.clamp(1, daysInMonth),
    );
    if (date.compareTo(widget.firstDate) < 0) {
      date = widget.firstDate;
    }
    if (date.compareTo(widget.lastDate) > 0) {
      date = widget.lastDate;
    }
    visibleYear = date.year;
    visibleMonth = date.month;
    return date;
  }

  bool _todayInRange() {
    final today = widget.today;
    return today.compareTo(widget.firstDate) >= 0 &&
        today.compareTo(widget.lastDate) <= 0;
  }

  bool _monthEnabled(int year, int month) {
    final monthStart = LocalDate(year, month, 1);
    final monthEnd = LocalDate(year, month, DateTime(year, month + 1, 0).day);
    return monthEnd.compareTo(widget.firstDate) >= 0 &&
        monthStart.compareTo(widget.lastDate) <= 0;
  }

  bool _yearEnabled(int year) {
    return year >= widget.firstDate.year && year <= widget.lastDate.year;
  }

  int _yearPageStartFor(int year) {
    return year - year % 12;
  }
}

enum _DatePickerMode { day, month, year }

class DateOptionTable extends StatelessWidget {
  const DateOptionTable({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final totalCells = ((children.length + 2) ~/ 3) * 3;
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var row = 0; row < totalCells ~/ 3; row++)
          TableRow(
            children: [
              for (var column = 0; column < 3; column++)
                Padding(
                  padding: EdgeInsets.only(
                    top: row == 0 ? 0 : 10,
                    left: column == 0 ? 0 : 5,
                    right: column == 2 ? 0 : 5,
                  ),
                  child: SizedBox(
                    height: 58,
                    child: row * 3 + column < children.length
                        ? children[row * 3 + column]
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class DatePickerHeader extends StatelessWidget {
  const DatePickerHeader({
    required this.mode,
    required this.visibleYear,
    required this.visibleMonth,
    required this.yearPageStart,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onYearTap,
    required this.onMonthTap,
  });

  final _DatePickerMode mode;
  final int visibleYear;
  final int visibleMonth;
  final int yearPageStart;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onYearTap;
  final VoidCallback onMonthTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: _previousTooltip,
          onPressed: canGoPrevious ? onPrevious : null,
          style: IconButton.styleFrom(
            backgroundColor: tokens.surface2,
            foregroundColor: tokens.ink,
          ),
        ),
        Expanded(child: Center(child: _buildTitle(context))),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: _nextTooltip,
          onPressed: canGoNext ? onNext : null,
          style: IconButton.styleFrom(
            backgroundColor: tokens.surface2,
            foregroundColor: tokens.ink,
          ),
        ),
      ],
    );
  }

  Widget _buildTitle(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    if (mode == _DatePickerMode.year) {
      return Text(
        '$yearPageStart-${yearPageStart + 11}年',
        style: Theme.of(context).textTheme.titleMedium,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: onYearTap,
          style: TextButton.styleFrom(
            foregroundColor: tokens.ink,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Text(
            '$visibleYear年',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: onMonthTap,
          style: TextButton.styleFrom(
            foregroundColor: tokens.ink,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Text(
            '$visibleMonth月',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }

  String get _previousTooltip {
    return switch (mode) {
      _DatePickerMode.day => '上个月',
      _DatePickerMode.month => '上一年',
      _DatePickerMode.year => '上一组年份',
    };
  }

  String get _nextTooltip {
    return switch (mode) {
      _DatePickerMode.day => '下个月',
      _DatePickerMode.month => '下一年',
      _DatePickerMode.year => '下一组年份',
    };
  }
}

class DateOptionCell extends StatelessWidget {
  const DateOptionCell({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primary : tokens.surface2,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: selected ? tokens.primary : tokens.line),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? Colors.white
                : enabled
                ? tokens.ink
                : tokens.subtle.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class DateCell extends StatelessWidget {
  const DateCell({
    required this.date,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.onSelected,
  });

  final LocalDate date;
  final LocalDate selectedDate;
  final LocalDate firstDate;
  final LocalDate lastDate;
  final ValueChanged<LocalDate> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final selected = date == selectedDate;
    final enabled =
        date.compareTo(firstDate) >= 0 && date.compareTo(lastDate) <= 0;
    return InkWell(
      onTap: enabled ? () => onSelected(date) : null,
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
        ),
        child: Text(
          '${date.day}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? Colors.white
                : enabled
                ? tokens.ink
                : tokens.subtle.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

InputDecoration numberInputDecoration({String? labelText, String? suffixText}) {
  return InputDecoration(labelText: labelText, suffixText: suffixText);
}

int displayPercentForThresholds({
  required double percent,
  required double notOverdueUpperLimit,
  required double overdueUpperLimit,
}) {
  var display = percent.round();
  if (percent < notOverdueUpperLimit &&
      display >= notOverdueUpperLimit.ceil()) {
    display = notOverdueUpperLimit.ceil() - 1;
  }
  if (percent < overdueUpperLimit && display >= overdueUpperLimit.ceil()) {
    display = overdueUpperLimit.ceil() - 1;
  }
  return display;
}

String formatPercent(int percent) {
  return percent > 999 ? '999%+' : '$percent%';
}

String itemRuleText(MaintenanceItem item) {
  final rules = <String>[];
  if (item.remindByMileage) {
    rules.add(formatCompactMileageText(item.mileageIntervalKm ?? 0));
  }
  if (item.remindByTime) {
    rules.add(formatCompactTimeText(item.timeIntervalMonths ?? 0));
  }
  return rules.isEmpty ? '提醒：未设置' : '提醒：${rules.join('/')}';
}

String defaultItemRuleText(VehicleDefaultMaintenanceItem item) {
  final rules = <String>[];
  if (item.remindByMileage) {
    rules.add(formatCompactMileageText(item.mileageIntervalKm ?? 0));
  }
  if (item.remindByTime) {
    rules.add(formatCompactTimeText(item.timeIntervalMonths ?? 0));
  }
  return rules.isEmpty ? '提醒：未设置' : '提醒：${rules.join('/')}';
}

String normalizeItemName(String value) => value.trim();

MaintenanceItem maintenanceItemFromDefault(
  VehicleDefaultMaintenanceItem item,
  SyncMetadata sync,
) {
  return MaintenanceItem(
    carsId: 0,
    name: item.itemName,
    enabled: true,
    remindByMileage: item.remindByMileage,
    remindByTime: item.remindByTime,
    mileageIntervalKm: item.mileageIntervalKm,
    timeIntervalMonths: item.timeIntervalMonths,
    notOverdueUpperLimit: item.notOverdueUpperLimit,
    overdueUpperLimit: item.overdueUpperLimit,
    sortOrder: item.sortOrder,
    sync: sync,
  );
}

List<String> recordItemNameList(
  MaintenanceRecord record,
  List<MaintenanceItem> items,
) {
  return record.itemIds
      .map((id) => itemById(items, id)?.name ?? '未知项目')
      .toList();
}

MaintenanceItem? itemById(List<MaintenanceItem> items, int itemId) {
  for (final item in items) {
    if (item.id == itemId) {
      return item;
    }
  }
  return null;
}

String formatMoney(int costCents) {
  return '¥${(costCents / 100).toStringAsFixed(2)}';
}

String formatMileageKm(int value) {
  return '${formatNumber(value)}km';
}

String formatCarAge(LocalDate roadDate, LocalDate today) {
  final months = roadDate.monthsUntil(today).clamp(0, 1200);
  final years = months / 12;
  final text = years.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$text年';
}

String formatCompactMileageText(int value) {
  if (value >= 10000) {
    final wan = value / 10000;
    final text = wan == wan.roundToDouble()
        ? wan.toStringAsFixed(0)
        : wan.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return '$text万公里';
  }
  return '${formatNumber(value)}公里';
}

String formatCompactTimeText(int months) {
  if (months < 12) {
    return '$months个月';
  }
  if (months % 12 == 0) {
    return '${months ~/ 12}年';
  }
  final years = months / 12;
  final text = years.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$text年';
}

String mileageReminderText(int remainingKm) {
  if (remainingKm > 0) {
    return '里程：距离下次约 ${formatNumber(remainingKm)} 公里';
  }
  if (remainingKm == 0) {
    return '里程：已到期';
  }
  return '里程：已超 ${formatNumber(remainingKm.abs())} 公里';
}

String timeReminderText(int remainingDays) {
  if (remainingDays > 0) {
    return '时间：距离下次约 ${formatReminderDuration(remainingDays)}';
  }
  if (remainingDays == 0) {
    return '时间：今日到期';
  }
  return '时间：已超 ${formatReminderDuration(remainingDays.abs())}';
}

String formatReminderDuration(int days) {
  if (days < 30) {
    return '$days天';
  }
  if (days < 365) {
    return '${days ~/ 30}个月';
  }
  final months = days ~/ 30;
  final years = months ~/ 12;
  final restMonths = months % 12;
  if (restMonths == 0) {
    return '$years年';
  }
  return '$years年$restMonths个月';
}

Future<void> applyCar(BuildContext context, WidgetRef ref, int carId) async {
  await ref.read(lunioRepositoryProvider).setAppliedCarId(carId);
  invalidateVehicleProviders(ref);
}

Future<void> setThemeModePreference(
  BuildContext context,
  WidgetRef ref,
  ThemeMode mode,
) async {
  final value = switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
  await ref
      .read(lunioRepositoryProvider)
      .setPreferenceValue('themeMode', value);
  invalidatePreferenceProviders(ref);
}

Future<T?> showLunioModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  Color? backgroundColor,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      final child = Material(
        type: MaterialType.transparency,
        child: builder(context),
      );
      return _LunioModalBackdrop(
        alignment: Alignment.bottomCenter,
        barrierDismissible: barrierDismissible,
        useSafeArea: false,
        child: FractionallySizedBox(
          widthFactor: 1,
          child: backgroundColor == Colors.transparent
              ? child
              : _LunioDefaultSheetSurface(
                  showDragHandle: showDragHandle,
                  child: child,
                ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

Future<T?> showLunioDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _LunioModalBackdrop(
        alignment: Alignment.center,
        barrierDismissible: barrierDismissible,
        useSafeArea: true,
        child: builder(context),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final scale = Tween<double>(
        begin: 0.98,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: scale, child: child),
      );
    },
  );
}

class _LunioModalBackdrop extends StatelessWidget {
  const _LunioModalBackdrop({
    required this.alignment,
    required this.barrierDismissible,
    required this.useSafeArea,
    required this.child,
  });

  final AlignmentGeometry alignment;
  final bool barrierDismissible;
  final bool useSafeArea;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrimOpacity = isDark ? 0.30 : 0.18;
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: scrimOpacity),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: barrierDismissible
                  ? () => Navigator.of(context).maybePop()
                  : null,
            ),
          ),
          if (useSafeArea)
            SafeArea(
              child: _LunioModalContent(alignment: alignment, child: child),
            )
          else
            _LunioModalContent(alignment: alignment, child: child),
        ],
      ),
    );
  }
}

class _LunioModalContent extends StatelessWidget {
  const _LunioModalContent({required this.alignment, required this.child});

  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: GestureDetector(onTap: () {}, child: child),
    );
  }
}

class _LunioDefaultSheetSurface extends StatelessWidget {
  const _LunioDefaultSheetSurface({
    required this.showDragHandle,
    required this.child,
  });

  final bool showDragHandle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.radiusXl),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.18),
            blurRadius: 54,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle) ...[
            const SizedBox(height: 8),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: tokens.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

Future<void> deleteCar(BuildContext context, WidgetRef ref, Car car) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: '删除车辆',
    message: '确定删除 ${car.brand} ${car.model}？相关项目和记录会同步删除。',
    confirmLabel: '删除',
  );
  if (confirmed != true || car.id == null) {
    return;
  }
  await ref.read(lunioRepositoryProvider).deleteCar(car.id!);
  invalidateVehicleProviders(ref);
}

Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) {
  return showLunioDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      final confirmColor = destructive ? tokens.danger : tokens.primary;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.line),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.16),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LunioSecondaryButton(
                      label: '取消',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            tokens.radiusMedium,
                          ),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showMessageDialog({
  required BuildContext context,
  required String title,
  required String message,
  required StatusOverlayTone tone,
}) {
  return showLunioDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      final toneColor = statusToneColor(tokens, tone);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.line),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.16),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusToneIcon(tone), color: toneColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: toneColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusMedium),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('确认'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void dismissTransientUi(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  hideStatusOverlay();
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}

enum StatusOverlayTone { success, error, info }

OverlayEntry? _statusOverlayEntry;

void hideStatusOverlay() {
  _statusOverlayEntry?.remove();
  _statusOverlayEntry = null;
}

void showStatusOverlay(
  BuildContext context,
  String message,
  StatusOverlayTone tone,
) {
  final tokens = Theme.of(context).extension<LunioTokens>()!;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    return;
  }
  hideStatusOverlay();
  final entry = OverlayEntry(
    builder: (context) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _StatusOverlay(
            message: message,
            tokens: tokens,
            tone: tone,
            onDismiss: hideStatusOverlay,
          ),
        ),
      );
    },
  );
  _statusOverlayEntry = entry;
  overlay.insert(entry);
}

class _StatusOverlay extends StatefulWidget {
  const _StatusOverlay({
    required this.message,
    required this.tokens,
    required this.tone,
    required this.onDismiss,
  });

  final String message;
  final LunioTokens tokens;
  final StatusOverlayTone tone;
  final VoidCallback onDismiss;

  @override
  State<_StatusOverlay> createState() => _StatusOverlayState();
}

class _StatusOverlayState extends State<_StatusOverlay> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 1600), widget.onDismiss);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final toneColor = statusToneColor(tokens, widget.tone);
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.line),
          boxShadow: [
            BoxShadow(
              color: tokens.ink.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusToneIcon(widget.tone), color: toneColor, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color statusToneColor(LunioTokens tokens, StatusOverlayTone tone) {
  return switch (tone) {
    StatusOverlayTone.success => tokens.success,
    StatusOverlayTone.error => tokens.danger,
    StatusOverlayTone.info => tokens.primary,
  };
}

IconData statusToneIcon(StatusOverlayTone tone) {
  return switch (tone) {
    StatusOverlayTone.success => Icons.check_circle_outline,
    StatusOverlayTone.error => Icons.error_outline,
    StatusOverlayTone.info => Icons.info_outline,
  };
}

bool isUniqueConstraintError(Object error) {
  final message = error.toString();
  return message.contains('UNIQUE constraint') ||
      message.contains('SqliteException(2067)');
}

String friendlyError(Object error) {
  final message = error.toString();
  if (message.contains('这辆车当天')) {
    return message.replaceFirst('Bad state: ', '');
  }
  if (message.contains('UNIQUE constraint') ||
      message.contains('SqliteException(2067')) {
    return '这条数据已经保存过了';
  }
  if (message.contains('At least one maintenance item must stay enabled')) {
    return '至少保留一个可用保养项目';
  }
  if (message.contains('Maintenance item has history records')) {
    return '已有保养记录的项目不能删除';
  }
  if (message.contains('contains missing items')) {
    return '选择的保养项目不存在，请重新选择';
  }
  if (message.contains('items from another car')) {
    return '保养项目不属于当前车辆，请重新选择';
  }
  return '操作失败，请稍后重试';
}

String formatDateForUser(LocalDate date) {
  return '${date.year}年${date.month}月${date.day}日';
}

String formatNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final fromEnd = text.length - i;
    buffer.write(text[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

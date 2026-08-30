// 自绘日期选择器（底部 sheet 形态，不是系统 DatePickerDialog）。
//
// 三级模式原地切换（符合产品"避免把下方内容挤出视野"的约定）：
//   日历网格（day） ⇄ 12 个月网格（month） ⇄ 12 年一页的年份网格（year）
// 顶部"xxxx年/xx月"文字可点击直接跳对应模式；左右箭头翻页；
// "今天"快捷按钮（仅当 today 在可选范围内显示）。
//
// 使用方：记录表单日期、车辆上路日期、手动日期设置
// （入口 showSimpleDatePicker，返回 null 表示取消）。
// 范围约束 firstDate~lastDate 之外的格子置灰不可选。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';

import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import 'modal_feedback.dart';

/// 日期选择入口：弹出 sheet，确定返回所选日期，取消/关闭返回 null。
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

/// 选择器主体（StatefulWidget：持有选中日期与当前浏览的年/月/模式）。
/// 状态：selectedDate（结果）+ visibleYear/Month（正在浏览哪页）+ mode。
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

  // ---- 三个网格的构建 ----

  /// 日历网格：周一开头的 7 列表；月前置空、越界格子空 SizedBox 占位。
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

/// 月份网格（3 列 × 4 行）。
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

/// 年份网格（12 年一页）。
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

// ---- 翻页与边界处理：所有方法都保证 visibleYear/Month 不越出
// firstDate~lastDate 范围，selectedDate 钳到合法日期 ----

  /// 能否向前翻（按模式判断是否已到下限）。
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

  /// 跨年进退月份。
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

  /// 把选中日钳到"当前浏览月"的合法日期（如 3.31 切到 2 月 → 2.28/29，
  /// 再整体钳到 first/last 范围），并同步 visible 年月。
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

/// 三级模式枚举。
enum _DatePickerMode { day, month, year }

/// 3 列选项网格（月/年模式共用；不足 3 的倍数补空位）。
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

/// 顶部导航条：左右翻页箭头（到边界禁用）+ 可点击的年/月标题。
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

/// 月/年格子。
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

/// 日历日期格（选中=主色底白字；范围外置灰不可点）。
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

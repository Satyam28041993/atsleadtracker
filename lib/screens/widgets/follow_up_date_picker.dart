import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Follow-up date dialog with explicit Month / Year dropdowns, quick picks
/// (Today, Tomorrow, +3 days, Next week) and a day grid for the chosen month.
///
/// Returns the picked date (time stripped) or `null` when cancelled.
Future<DateTime?> showFollowUpDatePicker(
  BuildContext context, {
  DateTime? initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Follow-up date',
}) {
  final first = _dateOnly(firstDate);
  final last = _dateOnly(lastDate);
  var initial = _dateOnly(initialDate ?? DateTime.now());
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  return showDialog<DateTime>(
    context: context,
    builder: (context) => _FollowUpDatePickerDialog(
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      title: title,
    ),
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class _FollowUpDatePickerDialog extends StatefulWidget {
  const _FollowUpDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  @override
  State<_FollowUpDatePickerDialog> createState() =>
      _FollowUpDatePickerDialogState();
}

class _FollowUpDatePickerDialogState extends State<_FollowUpDatePickerDialog> {
  late DateTime _selected;

  /// First day of the month currently shown in the day grid.
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _visibleMonth = DateTime(_selected.year, _selected.month);
  }

  bool _inRange(DateTime d) =>
      !d.isBefore(widget.firstDate) && !d.isAfter(widget.lastDate);

  List<int> get _years => [
    for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) y,
  ];

  /// Months of [year] that overlap the allowed range.
  List<int> _monthsFor(int year) {
    final start = year == widget.firstDate.year ? widget.firstDate.month : 1;
    final end = year == widget.lastDate.year ? widget.lastDate.month : 12;
    return [for (var m = start; m <= end; m++) m];
  }

  /// Moves the grid to [year]/[month] and keeps the same day when possible.
  void _showMonth(int year, int month) {
    final months = _monthsFor(year);
    final m = month.clamp(months.first, months.last);
    final daysInMonth = DateUtils.getDaysInMonth(year, m);
    var candidate = DateTime(year, m, _selected.day.clamp(1, daysInMonth));
    if (candidate.isBefore(widget.firstDate)) candidate = widget.firstDate;
    if (candidate.isAfter(widget.lastDate)) candidate = widget.lastDate;
    setState(() {
      _visibleMonth = DateTime(year, m);
      _selected = candidate;
    });
  }

  void _quickPick(DateTime d) {
    final day = _dateOnly(d);
    if (!_inRange(day)) return;
    setState(() {
      _selected = day;
      _visibleMonth = DateTime(day.year, day.month);
    });
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    // Plain DropdownButton (not the FormField variant) so the shown value
    // follows the calendar when the user pages months with the arrows.
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            for (final item in items)
              DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _dateOnly(DateTime.now());
    final quickPicks = <String, DateTime>{
      'Today': today,
      'Tomorrow': today.add(const Duration(days: 1)),
      '+3 days': today.add(const Duration(days: 3)),
      'Next week': today.add(const Duration(days: 7)),
    };
    final monthNames = DateFormat.MMMM();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only the body scrolls so Cancel / OK stay visible on short
            // screens.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEE, d MMM yyyy').format(_selected),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final entry in quickPicks.entries)
                          if (_inRange(entry.value))
                            ChoiceChip(
                              label: Text(entry.key),
                              selected: DateUtils.isSameDay(
                                _selected,
                                entry.value,
                              ),
                              onSelected: (_) => _quickPick(entry.value),
                            ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _dropdown<int>(
                            label: 'Month',
                            value: _visibleMonth.month,
                            items: _monthsFor(_visibleMonth.year),
                            itemLabel: (m) =>
                                monthNames.format(DateTime(2000, m)),
                            onChanged: (m) => _showMonth(_visibleMonth.year, m),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: _dropdown<int>(
                            label: 'Year',
                            value: _visibleMonth.year,
                            items: _years,
                            itemLabel: (y) => '$y',
                            onChanged: (y) =>
                                _showMonth(y, _visibleMonth.month),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    CalendarDatePicker(
                      // New key per month so the grid jumps when dropdowns change.
                      key: ValueKey(_visibleMonth),
                      initialDate: _selected,
                      firstDate: widget.firstDate,
                      lastDate: widget.lastDate,
                      initialCalendarMode: DatePickerMode.day,
                      onDateChanged: (d) =>
                          setState(() => _selected = _dateOnly(d)),
                      onDisplayedMonthChanged: (m) {
                        // Arrow navigation inside the grid: keep dropdowns in sync
                        // without rebuilding the grid (would reset its animation).
                        if (m.year != _visibleMonth.year ||
                            m.month != _visibleMonth.month) {
                          setState(
                            () => _visibleMonth = DateTime(m.year, m.month),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

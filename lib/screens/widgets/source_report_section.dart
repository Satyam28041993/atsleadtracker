import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';

/// Opens the lead list modal for a set of ids. The dashboard's own
/// `openLeads` (with its optional named args) satisfies this signature.
typedef SourceReportOpenLeads = void Function(String title, List<String> leadIds);

enum _SourceView { time, status, employee }

/// Source × (time | status | employee) report table.
///
/// Rows stay constant (one per lead source); the segmented control swaps the
/// column group so the table never grows to thirty columns. Expanding a row
/// splits it employee-wise using the same columns, which is how
/// source × employee × status is reached without another axis.
class SourceReportSection extends StatefulWidget {
  const SourceReportSection({
    super.key,
    required this.report,
    required this.colors,
    required this.onOpenLeads,
    this.showEmployeeView = true,
  });

  final SourceReport report;
  final List<Color> colors;
  final SourceReportOpenLeads onOpenLeads;

  /// False when the dashboard is already filtered to one employee — a
  /// single-column employee view is noise.
  final bool showEmployeeView;

  @override
  State<SourceReportSection> createState() => _SourceReportSectionState();
}

class _SourceReportSectionState extends State<SourceReportSection> {
  static const Color _border = Color(0xFFE6EAF2);
  static const Color _hairline = Color(0xFFF1F4F9);
  static const Color _link = Color(0xFF245DAF);
  static const Color _muted = Color(0xFFB6BEC9);
  static const Color _subRowBg = Color(0xFFF8FAFC);

  static const double _wonWidth = 92;
  static const double _headerHeight = 42;
  static const double _rowHeight = 46;
  static const double _subRowHeight = 40;

  _SourceView _view = _SourceView.time;
  bool _showValue = false;
  final Set<String> _expanded = <String>{};

  /// Column metrics, tightened on narrow screens so the frozen source column
  /// never eats the scrollable half. Set once per layout pass in [_buildTable].
  double _labelWidth = 214;
  double _totalWidth = 74;
  double _colWidth = 104;

  @override
  void didUpdateWidget(covariant SourceReportSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showEmployeeView && _view == _SourceView.employee) {
      _view = _SourceView.status;
    }
  }

  List<({String key, String label})> get _columns {
    switch (_view) {
      case _SourceView.time:
        return kSourceTimeBuckets;
      case _SourceView.status:
        return [
          for (final s in widget.report.statuses) (key: s, label: s),
        ];
      case _SourceView.employee:
        return [
          for (final e in widget.report.employees) (key: e.uid, label: e.name),
        ];
    }
  }

  SourceCell _cellOf(SourceReportRow row, String key) {
    switch (_view) {
      case _SourceView.time:
        return row.time(key);
      case _SourceView.status:
        return row.status(key);
      case _SourceView.employee:
        return row.employee(key);
    }
  }

  SourceCell _subCellOf(SourceReportRow row, String uid, String key) {
    switch (_view) {
      case _SourceView.time:
        return row.employeeTime(uid, key);
      case _SourceView.status:
        return row.employeeStatus(uid, key);
      case _SourceView.employee:
        return SourceCell.empty;
    }
  }

  bool get _canExpand => _view != _SourceView.employee;

  static String _money(double v) {
    if (v <= 0) return '—';
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)} K';
    return '₹${v.toStringAsFixed(0)}';
  }

  String _cellText(SourceCell cell) {
    if (cell.isEmpty) return '—';
    return _showValue ? _money(cell.value) : '${cell.count}';
  }

  void _open(String title, SourceCell cell) {
    if (cell.isEmpty) return;
    widget.onOpenLeads(title, cell.leadIds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = widget.report;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 16),
            if (report.isEmpty)
              SizedBox(
                height: 140,
                child: Center(
                  child: Text(
                    'No source data yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else ...[
              _buildTable(theme),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 13, color: _muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Time columns are absolute and ignore the date filter. '
                      'Status and employee columns are a snapshot of all leads; '
                      'Won / Won ₹ follow the selected period.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Lead Source Report',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _canExpand
              ? 'Tap any number to open its leads · tap a source to split it employee-wise'
              : 'Leads by source and owner · tap any number to open its leads',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ChipGroup(
          items: [
            (value: _SourceView.time, label: 'Time', icon: Icons.event),
            (
              value: _SourceView.status,
              label: 'Status',
              icon: Icons.donut_small
            ),
            if (widget.showEmployeeView)
              (
                value: _SourceView.employee,
                label: 'Employee',
                icon: Icons.people_alt_outlined
              ),
          ],
          selected: _view,
          onSelected: (v) => setState(() {
            _view = v;
            if (!_canExpand) _expanded.clear();
          }),
        ),
        _ChipGroup<bool>(
          items: const [
            (value: false, label: 'Count', icon: Icons.tag),
            (value: true, label: 'Value', icon: Icons.currency_rupee),
          ],
          selected: _showValue,
          onSelected: (v) => setState(() => _showValue = v),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), controls],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            controls,
          ],
        );
      },
    );
  }

  Widget _buildTable(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        _labelWidth = compact ? 132 : 214;
        _totalWidth = compact ? 58 : 74;
        _colWidth = compact ? 88 : 104;
        return _buildTableBody(theme);
      },
    );
  }

  Widget _buildTableBody(ThemeData theme) {
    final report = widget.report;
    final columns = _columns;

    // Frozen left block (source + total) and the scrolling block must line up
    // row for row, so every row here has a fixed height.
    final leftChildren = <Widget>[_leftHeader(theme)];
    final rightChildren = <Widget>[_rightHeader(theme, columns)];

    for (var i = 0; i < report.rows.length; i++) {
      final row = report.rows[i];
      final color = widget.colors[i % widget.colors.length];
      final isOpen = _expanded.contains(row.source);

      leftChildren.add(_leftRow(theme, row, color, isOpen));
      rightChildren.add(_rightRow(theme, row, columns));

      if (isOpen && _canExpand) {
        for (final owner in row.ownersFrom(report.employees)) {
          leftChildren.add(_leftSubRow(theme, row, owner));
          rightChildren.add(_rightSubRow(theme, row, owner, columns));
        }
      }
    }

    leftChildren.add(_leftTotal(theme, report.grandTotal));
    rightChildren.add(_rightTotal(theme, report.grandTotal, columns));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(mainAxisSize: MainAxisSize.min, children: leftChildren),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rightChildren,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- frozen left column ----------

  BoxDecoration _rowDecoration({
    bool isTotal = false,
    bool isSub = false,
    bool isHeader = false,
  }) {
    return BoxDecoration(
      color: isSub ? _subRowBg : null,
      border: Border(
        bottom: BorderSide(
          color: isHeader ? _border : _hairline,
          width: isHeader ? 1 : 0.8,
        ),
        top: isTotal ? const BorderSide(color: _border, width: 1.2) : BorderSide.none,
      ),
    );
  }

  TextStyle? _headerStyle(ThemeData theme) => theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 11,
        height: 1.15,
        color: theme.colorScheme.onSurfaceVariant,
      );

  Widget _leftHeader(ThemeData theme) => Container(
        width: _labelWidth + _totalWidth,
        height: _headerHeight,
        decoration: _rowDecoration(isHeader: true),
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          children: [
            Expanded(child: Text('Source', style: _headerStyle(theme))),
            SizedBox(
              width: _totalWidth,
              child: Text(
                'Total',
                textAlign: TextAlign.right,
                style: _headerStyle(theme),
              ),
            ),
          ],
        ),
      );

  Widget _leftRow(
    ThemeData theme,
    SourceReportRow row,
    Color color,
    bool isOpen,
  ) {
    return Container(
      width: _labelWidth + _totalWidth,
      height: _rowHeight,
      decoration: _rowDecoration(),
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _canExpand
                  ? () => setState(() {
                        if (!_expanded.remove(row.source)) {
                          _expanded.add(row.source);
                        }
                      })
                  : () => _open('${row.source} — all leads', row.total),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    if (_canExpand)
                      AnimatedRotation(
                        turns: isOpen ? 0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Color(0xFF94A3B8),
                        ),
                      )
                    else
                      const SizedBox(width: 4),
                    const SizedBox(width: 2),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.source,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _numberCell(
            theme,
            row.total,
            width: _totalWidth,
            bold: true,
            onTap: () => _open('${row.source} — all leads', row.total),
          ),
        ],
      ),
    );
  }

  Widget _leftSubRow(
    ThemeData theme,
    SourceReportRow row,
    SourceReportEmployee owner,
  ) {
    final cell = row.employee(owner.uid);
    return Container(
      width: _labelWidth + _totalWidth,
      height: _subRowHeight,
      decoration: _rowDecoration(isSub: true),
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          const SizedBox(width: 30),
          Expanded(
            child: Text(
              owner.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: owner.isUnassigned
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
                fontStyle: owner.isUnassigned ? FontStyle.italic : null,
              ),
            ),
          ),
          _numberCell(
            theme,
            cell,
            width: _totalWidth,
            onTap: () => _open('${row.source} › ${owner.name}', cell),
          ),
        ],
      ),
    );
  }

  Widget _leftTotal(ThemeData theme, SourceReportRow total) => Container(
        width: _labelWidth + _totalWidth,
        height: _rowHeight,
        decoration: _rowDecoration(isTotal: true),
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          children: [
            const SizedBox(width: 30),
            Expanded(
              child: Text(
                'All sources',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _numberCell(
              theme,
              total.total,
              width: _totalWidth,
              bold: true,
              onTap: () => _open('All sources — all leads', total.total),
            ),
          ],
        ),
      );

  // ---------- scrolling right block ----------

  Widget _rightHeader(
    ThemeData theme,
    List<({String key, String label})> columns,
  ) {
    return Container(
      height: _headerHeight,
      decoration: _rowDecoration(isHeader: true),
      child: Row(
        children: [
          for (final col in columns)
            SizedBox(
              width: _colWidth,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _open(
                  '${col.label} — all sources',
                  _cellOf(widget.report.grandTotal, col.key),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      col.label,
                      maxLines: 2,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: _headerStyle(theme),
                    ),
                  ),
                ),
              ),
            ),
          _pinnedHeader(theme, 'Won'),
          _pinnedHeader(theme, 'Won ₹'),
        ],
      ),
    );
  }

  Widget _pinnedHeader(ThemeData theme, String label) => SizedBox(
        width: _wonWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(label, style: _headerStyle(theme)),
          ),
        ),
      );

  Widget _rightRow(
    ThemeData theme,
    SourceReportRow row,
    List<({String key, String label})> columns,
  ) {
    return Container(
      height: _rowHeight,
      decoration: _rowDecoration(),
      child: Row(
        children: [
          for (final col in columns)
            _numberCell(
              theme,
              _cellOf(row, col.key),
              width: _colWidth,
              onTap: () => _open(
                '${row.source} › ${col.label}',
                _cellOf(row, col.key),
              ),
            ),
          _wonCells(theme, row),
        ],
      ),
    );
  }

  Widget _rightSubRow(
    ThemeData theme,
    SourceReportRow row,
    SourceReportEmployee owner,
    List<({String key, String label})> columns,
  ) {
    return Container(
      height: _subRowHeight,
      decoration: _rowDecoration(isSub: true),
      child: Row(
        children: [
          for (final col in columns)
            _numberCell(
              theme,
              _subCellOf(row, owner.uid, col.key),
              width: _colWidth,
              onTap: () => _open(
                '${row.source} › ${owner.name} › ${col.label}',
                _subCellOf(row, owner.uid, col.key),
              ),
            ),
          const SizedBox(width: _wonWidth * 2),
        ],
      ),
    );
  }

  Widget _rightTotal(
    ThemeData theme,
    SourceReportRow total,
    List<({String key, String label})> columns,
  ) {
    return Container(
      height: _rowHeight,
      decoration: _rowDecoration(isTotal: true),
      child: Row(
        children: [
          for (final col in columns)
            _numberCell(
              theme,
              _cellOf(total, col.key),
              width: _colWidth,
              bold: true,
              onTap: () => _open(
                'All sources › ${col.label}',
                _cellOf(total, col.key),
              ),
            ),
          _wonCells(theme, total, bold: true),
        ],
      ),
    );
  }

  Widget _wonCells(ThemeData theme, SourceReportRow row, {bool bold = false}) {
    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
      color: row.wonCount > 0 ? const Color(0xFF2F9E44) : _muted,
    );
    return Row(
      children: [
        SizedBox(
          width: _wonWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(row.wonCount > 0 ? '${row.wonCount}' : '—',
                  style: style),
            ),
          ),
        ),
        SizedBox(
          width: _wonWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _money(row.wonValue),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _numberCell(
    ThemeData theme,
    SourceCell cell, {
    required double width,
    required VoidCallback onTap,
    bool bold = false,
  }) {
    final text = Text(
      _cellText(cell),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.textTheme.bodySmall?.copyWith(
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        color: cell.isEmpty ? _muted : _link,
        decoration: cell.isEmpty ? null : TextDecoration.underline,
        decorationColor: _link.withValues(alpha: 0.35),
      ),
    );

    return SizedBox(
      width: width,
      child: cell.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(alignment: Alignment.centerRight, child: text),
            )
          : InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(alignment: Alignment.centerRight, child: text),
              ),
            ),
    );
  }
}

/// Compact segmented control used for the view and count/value switches.
class _ChipGroup<T> extends StatelessWidget {
  const _ChipGroup({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<({T value, String label, IconData icon})> items;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6EAF2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelected(item.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: item.value == selected ? Colors.white : null,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: item.value == selected
                      ? const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 14,
                      color: item.value == selected
                          ? const Color(0xFF245DAF)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: item.value == selected
                            ? const Color(0xFF245DAF)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/time_card_table.dart';

class TimeCardReportTable extends StatelessWidget {
  const TimeCardReportTable({
    super.key,
    required this.rows,
    this.compact = false,
    this.forExport = false,
    this.employeeName = '',
    this.onEditRow,
    this.rowActionIcon = Icons.edit_rounded,
  });

  final List<TimeCardTableRow> rows;
  final bool compact;
  final bool forExport;
  final String employeeName;
  final ValueChanged<TimeCardTableRow>? onEditRow;
  final IconData rowActionIcon;

  @override
  Widget build(BuildContext context) {
    if (forExport) {
      return _ExportTable(rows: rows);
    }

    final colors = AppColors.of(context);
    final showEdit = onEditRow != null;
    final minWidth = compact
        ? (showEdit ? 820.0 : 760.0)
        : (showEdit ? 940.0 : 880.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final expandColumns = maxWidth.isFinite && maxWidth >= minWidth;
        final tableWidth = expandColumns ? maxWidth : minWidth;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: _TableBody(
                  rows: rows,
                  employeeName: employeeName,
                  headerColor: colors.header,
                  borderColor: colors.border,
                  textSecondary: colors.textSecondary,
                  highlightColor: AppColors.primary.withValues(alpha: 0.12),
                  onEditRow: onEditRow,
                  rowActionIcon: rowActionIcon,
                  expandColumns: expandColumns,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExportTable extends StatelessWidget {
  const _ExportTable({required this.rows});

  final List<TimeCardTableRow> rows;

  static const _header = Color(0xFFE6F3B8);
  static const _border = Color(0xFFD4E4A8);
  static const _textSecondary = Color(0xFF6B7280);
  static const _highlight = Color(0xFFF7FBEA);

  @override
  Widget build(BuildContext context) {
    return _TableBody(
      rows: rows,
      headerColor: _header,
      borderColor: _border,
      textSecondary: _textSecondary,
      highlightColor: _highlight,
      forExport: true,
      onEditRow: null,
      expandColumns: false,
    );
  }
}

class _TableBody extends StatelessWidget {
  const _TableBody({
    required this.rows,
    required this.headerColor,
    required this.borderColor,
    required this.textSecondary,
    required this.highlightColor,
    required this.onEditRow,
    this.rowActionIcon = Icons.edit_rounded,
    this.forExport = false,
    this.expandColumns = false,
    this.employeeName = '',
  });

  final List<TimeCardTableRow> rows;
  final Color headerColor;
  final Color borderColor;
  final Color textSecondary;
  final Color highlightColor;
  final ValueChanged<TimeCardTableRow>? onEditRow;
  final IconData rowActionIcon;
  final bool forExport;
  final bool expandColumns;
  final String employeeName;

  Map<int, TableColumnWidth> _columnWidths(bool showEdit) {
    if (!expandColumns) {
      var index = 0;
      return {
        if (!forExport) index++: const FixedColumnWidth(180), // Employee
        index++: const FixedColumnWidth(108), // Date
        index++: const FixedColumnWidth(52), // Day
        index++: const FixedColumnWidth(112), // Time in
        index++: const FixedColumnWidth(112), // Time out
        index++: const FixedColumnWidth(68), // Hours
        index++: const FixedColumnWidth(78), // Status
        if (showEdit) index: const FixedColumnWidth(56), // Edit
      };
    }

    var index = 0;
    return {
      if (!forExport) index++: const FlexColumnWidth(3), // Employee
      index++: const FlexColumnWidth(2.4), // Date
      index++: const FlexColumnWidth(1), // Day
      index++: const FlexColumnWidth(2.2), // Time in
      index++: const FlexColumnWidth(2.2), // Time out
      index++: const FlexColumnWidth(1.4), // Hours
      index++: const FlexColumnWidth(2), // Status
      if (showEdit) index: const FixedColumnWidth(56), // Edit
    };
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = forExport
        ? AppTheme.light().textTheme
        : Theme.of(context).textTheme;

    final showEdit = !forExport && onEditRow != null;
    final columnWidths = _columnWidths(showEdit);

    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder.all(color: borderColor, width: 1),
      children: [
        TableRow(
          decoration: BoxDecoration(color: headerColor),
          children: [
            if (!forExport) _HeadCell('Employee name', textTheme, forExport),
            _HeadCell('Date', textTheme, forExport),
            _HeadCell('Day', textTheme, forExport),
            _HeadCell('Time in', textTheme, forExport),
            _HeadCell('Time out', textTheme, forExport),
            _HeadCell('Hours', textTheme, forExport),
            _HeadCell('Status', textTheme, forExport),
            if (showEdit) _HeadCell('', textTheme, forExport),
          ],
        ),
        for (final row in rows)
          TableRow(
            decoration: BoxDecoration(
              color: row.isToday ? highlightColor : null,
            ),
            children: [
              if (!forExport)
                TableRowInkWell(
                  onTap: showEdit ? () => onEditRow?.call(row) : null,
                  child: _BodyCell(
                    row.hasEmployee ? row.employeeName : employeeName,
                    textTheme,
                  ),
                ),
              TableRowInkWell(
                onTap: showEdit ? () => onEditRow?.call(row) : null,
                child: _BodyCell(
                  row.workDate,
                  textTheme,
                  bold: row.isToday,
                ),
              ),
              TableRowInkWell(
                onTap: showEdit ? () => onEditRow?.call(row) : null,
                child: _BodyCell(
                  row.weekday,
                  textTheme,
                  muted: true,
                  mutedColor: textSecondary,
                ),
              ),
              TableRowInkWell(
                onTap: showEdit ? () => onEditRow?.call(row) : null,
                child: _BodyCell(row.timeIn, textTheme),
              ),
              TableRowInkWell(
                onTap: showEdit ? () => onEditRow?.call(row) : null,
                child: _BodyCell(
                  row.timeOut,
                  textTheme,
                  highlight: row.timeOut == 'Active',
                ),
              ),
              TableRowInkWell(
                onTap: showEdit ? () => onEditRow?.call(row) : null,
                child: _BodyCell(
                  row.duration,
                  textTheme,
                  bold: row.hasData,
                  accent: row.hasData,
                ),
              ),
              TableRowInkWell(
                onTap: showEdit ? () => onEditRow?.call(row) : null,
                child: _BodyCell(
                  row.status,
                  textTheme,
                  status: row.status,
                ),
              ),
              if (showEdit)
                TableRowInkWell(
                  onTap: () => onEditRow?.call(row),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Icon(
                        rowActionIcon,
                        size: 18,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.label, this.textTheme, this.forExport);

  final String label;
  final TextTheme textTheme;
  final bool forExport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 13.5,
          color: forExport ? AppColors.primaryDark : null,
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell(
    this.value,
    this.textTheme, {
    this.muted = false,
    this.bold = false,
    this.accent = false,
    this.highlight = false,
    this.status,
    this.mutedColor,
  });

  final String value;
  final TextTheme textTheme;
  final bool muted;
  final bool bold;
  final bool accent;
  final bool highlight;
  final String? status;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    Color? color;
    if (status == 'Present') {
      color = AppColors.success;
    } else if (status == 'Late') {
      color = const Color(0xFFD97706);
    } else if (status == 'Absent') {
      color = AppColors.error;
    } else if (status == 'On Leave') {
      color = AppColors.primaryDark;
    } else if (status == 'Off') {
      color = mutedColor ?? AppColors.of(context).textSecondary;
    } else if (status == 'Active') {
      color = AppColors.primaryDark;
    } else if (status == 'Done') {
      color = AppColors.success;
    } else if (highlight) {
      color = AppColors.primaryDark;
    } else if (accent) {
      color = AppColors.primaryDark;
    } else if (muted) {
      color = mutedColor ?? AppColors.of(context).textSecondary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium?.copyWith(
          fontSize: 13.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

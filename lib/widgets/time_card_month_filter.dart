import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/time_card_table.dart';

/// Month/day navigator for time card details (past and future months).
class TimeCardMonthFilter extends StatelessWidget {
  const TimeCardMonthFilter({
    super.key,
    required this.viewDate,
    required this.onViewDateChanged,
    this.compact = false,
  });

  final DateTime viewDate;
  final ValueChanged<DateTime> onViewDateChanged;
  final bool compact;

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return viewDate.year == now.year && viewDate.month == now.month;
  }

  Future<void> _openCalendar(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: viewDate,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Select month or day',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primaryDark,
                  onPrimary: Colors.white,
                  surface: AppColors.of(context).card,
                ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null) onViewDateChanged(_monthStart(picked));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = DateTime.now();

    final iconSize = compact ? 16.0 : 20.0;
    final cellPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 10);
    final gap = compact ? 4.0 : 6.0;

    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous month',
          compact: compact,
          onPressed: () =>
              onViewDateChanged(
                _monthStart(shiftCalendarMonth(viewDate, -1)),
              ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: Material(
            color: colors.card,
            borderRadius: BorderRadius.circular(compact ? 8 : 10),
            child: InkWell(
              onTap: () => _openCalendar(context),
              borderRadius: BorderRadius.circular(compact ? 8 : 10),
              child: Container(
                padding: cellPadding,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: iconSize,
                      color: AppColors.primaryDark,
                    ),
                    SizedBox(width: compact ? 6 : 8),
                    Expanded(
                      child: Text(
                        monthYearLabel(viewDate),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: compact ? 12 : null,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: compact ? 20 : 24,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: gap),
        _RoundIconButton(
          icon: Icons.chevron_right_rounded,
          tooltip: 'Next month',
          compact: compact,
          onPressed: () =>
              onViewDateChanged(
                _monthStart(shiftCalendarMonth(viewDate, 1)),
              ),
        ),
        if (!_isCurrentMonth) ...[
          SizedBox(width: compact ? 2 : 4),
          IconButton(
            tooltip: 'This month',
            onPressed: () => onViewDateChanged(
              DateTime(now.year, now.month, 1),
            ),
            icon: Icon(Icons.today_rounded, size: compact ? 18 : 24),
            color: AppColors.primaryDark,
            visualDensity: VisualDensity.compact,
            padding: compact ? EdgeInsets.zero : null,
            constraints: compact
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
          ),
        ],
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.compact = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: compact ? 18 : 24),
      color: AppColors.primaryDark,
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact
          ? const BoxConstraints(minWidth: 32, minHeight: 32)
          : null,
      style: IconButton.styleFrom(
        backgroundColor: colors.card,
        side: BorderSide(color: colors.border),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

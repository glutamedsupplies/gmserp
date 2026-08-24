import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/time_card_table.dart';

/// Month/day navigator for time card details (past and future months).
class TimeCardMonthFilter extends StatelessWidget {
  const TimeCardMonthFilter({
    super.key,
    required this.viewDate,
    required this.onViewDateChanged,
  });

  final DateTime viewDate;
  final ValueChanged<DateTime> onViewDateChanged;

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

    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous month',
          onPressed: () =>
              onViewDateChanged(
                _monthStart(shiftCalendarMonth(viewDate, -1)),
              ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Material(
            color: colors.card,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => _openCalendar(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 20,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        monthYearLabel(viewDate),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _RoundIconButton(
          icon: Icons.chevron_right_rounded,
          tooltip: 'Next month',
          onPressed: () =>
              onViewDateChanged(
                _monthStart(shiftCalendarMonth(viewDate, 1)),
              ),
        ),
        if (!_isCurrentMonth) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'This month',
            onPressed: () => onViewDateChanged(
              DateTime(now.year, now.month, 1),
            ),
            icon: const Icon(Icons.today_rounded),
            color: AppColors.primaryDark,
            visualDensity: VisualDensity.compact,
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: AppColors.primaryDark,
      style: IconButton.styleFrom(
        backgroundColor: colors.card,
        side: BorderSide(color: colors.border),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

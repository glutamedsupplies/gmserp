import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Interactive loading card used for page / gate spinners.
class AppLoadingCard extends StatelessWidget {
  const AppLoadingCard({
    super.key,
    this.title = 'Loading',
    this.message = 'Please wait…',
    this.compact = false,
  });

  final String title;
  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pad = compact
        ? const EdgeInsets.fromLTRB(16, 16, 16, 14)
        : const EdgeInsets.fromLTRB(22, 22, 22, 20);
    final spinner = compact ? 28.0 : 44.0;

    return Material(
      color: colors.card,
      elevation: compact ? 0 : 6,
      shadowColor: colors.shadow,
      borderRadius: BorderRadius.circular(compact ? 12 : 18),
      child: Container(
        padding: pad,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 12 : 18),
          border: Border.all(
            color: AppColors.primaryDark.withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: spinner,
              height: spinner,
              child: CircularProgressIndicator(
                strokeWidth: compact ? 2.6 : 3.2,
                color: AppColors.primaryDark,
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered loading state for full pages / auth gate.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({
    super.key,
    this.title = 'Loading',
    this.message = 'Please wait…',
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: AppLoadingCard(title: title, message: message),
        ),
      ),
    );
  }
}

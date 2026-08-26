import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'compact_page.dart';

enum FeedbackKind { success, danger, info, loading }

/// Shared palette for success (green), danger (red), info (orange), loading.
class FeedbackPalette {
  const FeedbackPalette({required this.accent, required this.icon});

  final Color accent;
  final IconData icon;

  static FeedbackPalette of(FeedbackKind kind) {
    switch (kind) {
      case FeedbackKind.success:
        return const FeedbackPalette(
          accent: AppColors.success,
          icon: Icons.check_circle_rounded,
        );
      case FeedbackKind.danger:
        return const FeedbackPalette(
          accent: AppColors.error,
          icon: Icons.error_rounded,
        );
      case FeedbackKind.info:
        return const FeedbackPalette(
          accent: AppColors.warning,
          icon: Icons.notifications_active_rounded,
        );
      case FeedbackKind.loading:
        return const FeedbackPalette(
          accent: AppColors.warning,
          icon: Icons.hourglass_top_rounded,
        );
    }
  }
}

/// Single visual card used by overlays, page loaders, and confirm dialogs.
class AppFeedbackCard extends StatelessWidget {
  const AppFeedbackCard({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    this.compact = false,
    this.showSpinner = false,
    this.onClose,
    this.progress,
    this.actions,
  });

  final FeedbackKind kind;
  final String title;
  final String message;
  final bool compact;

  /// When true, shows a spinner tinted with [kind]'s accent (green/red/orange).
  final bool showSpinner;
  final VoidCallback? onClose;

  /// 1 → 0 auto-dismiss progress bar (toasts only).
  final double? progress;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final palette = FeedbackPalette.of(kind);
    final density = CompactPageStyle.of(context);
    final isLoading = showSpinner || kind == FeedbackKind.loading;
    final radius = compact
        ? (density.compact ? 12.0 : 14.0)
        : (density.compact ? 16.0 : 18.0);
    final pad = compact
        ? EdgeInsets.fromLTRB(
            density.compact ? 14 : 16,
            density.compact ? 14 : 16,
            density.compact ? 14 : 16,
            density.compact ? 12 : 14,
          )
        : EdgeInsets.fromLTRB(
            density.compact ? 18 : 22,
            density.compact ? 18 : 22,
            density.compact ? 18 : 22,
            density.compact ? 16 : 20,
          );
    final spinnerSize = compact
        ? (density.compact ? 28.0 : 32.0)
        : (density.compact ? 44.0 : 52.0);
    final titleSize = density.compact ? (compact ? 14.0 : 15.0) : (compact ? 16.0 : 17.0);
    final messageSize = density.compact ? (compact ? 12.0 : 13.0) : (compact ? 14.0 : 15.0);

    return Material(
      color: colors.card,
      elevation: compact ? 0 : 10,
      shadowColor: colors.shadow,
      borderRadius: BorderRadius.circular(radius),
      child: Ink(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: palette.accent.withValues(alpha: 0.35),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: pad,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLoading)
                      SizedBox(
                        width: spinnerSize,
                        height: spinnerSize,
                        child: CircularProgressIndicator(
                          strokeWidth: compact ? 2.6 : 3.2,
                          color: palette.accent,
                        ),
                      )
                    else
                      Container(
                        width: density.compact ? (compact ? 34 : 42) : (compact ? 40 : 52),
                        height: density.compact ? (compact ? 34 : 42) : (compact ? 40 : 52),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(density.radius),
                        ),
                        child: Icon(
                          palette.icon,
                          color: palette.accent,
                          size: density.compact ? (compact ? 18 : 22) : (compact ? 22 : 26),
                        ),
                      ),
                    SizedBox(height: density.compact ? 12 : 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    SizedBox(height: density.titleSubtitleGap),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: messageSize,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                    ),
                    if (actions != null && actions!.isNotEmpty) ...[
                      SizedBox(height: compact ? 14 : 18),
                      Row(
                        children: [
                          for (var i = 0; i < actions!.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(child: actions![i]),
                          ],
                        ],
                      ),
                    ],
                    if (onClose != null && actions == null) ...[
                      SizedBox(height: compact ? 10 : 12),
                      TextButton(
                        onPressed: onClose,
                        child: Text(
                          'Dismiss',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: palette.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (progress != null)
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: palette.accent.withValues(alpha: 0.12),
                  color: palette.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

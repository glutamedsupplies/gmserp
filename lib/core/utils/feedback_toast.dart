import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum FeedbackKind { success, danger, info, loading }

/// Floating interactive feedback cards (success / danger / info / loading).
class FeedbackToast {
  FeedbackToast._();

  static OverlayEntry? _loadingEntry;
  static OverlayEntry? _toastEntry;
  static int _toastSeq = 0;

  static void showSuccess(
    BuildContext context,
    String message, {
    String title = 'Success',
    Duration duration = const Duration(seconds: 3),
  }) {
    _showToast(
      context,
      kind: FeedbackKind.success,
      title: title,
      message: message,
      duration: duration,
    );
  }

  static void showDanger(
    BuildContext context,
    String message, {
    String title = 'Something went wrong',
    Duration duration = const Duration(seconds: 4),
  }) {
    _showToast(
      context,
      kind: FeedbackKind.danger,
      title: title,
      message: message,
      duration: duration,
    );
  }

  static void showInfo(
    BuildContext context,
    String message, {
    String title = 'Notice',
    Duration duration = const Duration(seconds: 3),
  }) {
    _showToast(
      context,
      kind: FeedbackKind.info,
      title: title,
      message: message,
      duration: duration,
    );
  }

  /// Full-screen interactive loading card (login, logout, long actions).
  static void showLoading(
    BuildContext context, {
    String title = 'Please wait',
    String message = 'Working…',
  }) {
    hideLoading();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _loadingEntry = OverlayEntry(
      builder: (ctx) {
        return _FeedbackLoadingBarrier(
          title: title,
          message: message,
        );
      },
    );
    overlay.insert(_loadingEntry!);
  }

  static void hideLoading() {
    _loadingEntry?.remove();
    _loadingEntry = null;
  }

  static void hideToast() {
    _toastEntry?.remove();
    _toastEntry = null;
  }

  static void _showToast(
    BuildContext context, {
    required FeedbackKind kind,
    required String title,
    required String message,
    required Duration duration,
  }) {
    hideLoading();
    hideToast();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final id = ++_toastSeq;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Positioned(
          left: 16,
          right: 16,
          bottom: 20 + bottom,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _InteractiveFeedbackCard(
                  key: ValueKey('feedback-$id'),
                  kind: kind,
                  title: title,
                  message: message,
                  duration: duration,
                  onClose: () {
                    if (_toastEntry == entry) {
                      hideToast();
                    }
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
    _toastEntry = entry;
    overlay.insert(entry);
  }
}

class _InteractiveFeedbackCard extends StatefulWidget {
  const _InteractiveFeedbackCard({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    required this.duration,
    required this.onClose,
  });

  final FeedbackKind kind;
  final String title;
  final String message;
  final Duration duration;
  final VoidCallback onClose;

  @override
  State<_InteractiveFeedbackCard> createState() =>
      _InteractiveFeedbackCardState();
}

class _InteractiveFeedbackCardState extends State<_InteractiveFeedbackCard>
    with TickerProviderStateMixin {
  late final AnimationController _progress;
  late final AnimationController _appear;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _appear, curve: Curves.easeOut);

    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onClose();
      }
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _FeedbackTheme.of(widget.kind);
    final colors = AppColors.of(context);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Dismissible(
          key: ValueKey('dismiss-${widget.key}'),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => widget.onClose(),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onClose,
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.accent.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: theme.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                theme.icon,
                                color: theme.accent,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.message,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.35,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Dismiss',
                              onPressed: widget.onClose,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _progress,
                        builder: (context, _) {
                          return LinearProgressIndicator(
                            value: 1 - _progress.value,
                            minHeight: 3,
                            backgroundColor:
                                theme.accent.withValues(alpha: 0.12),
                            color: theme.accent,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackLoadingBarrier extends StatelessWidget {
  const _FeedbackLoadingBarrier({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = _FeedbackTheme.of(FeedbackKind.loading);

    return AbsorbPointer(
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Material(
              color: colors.card,
              elevation: 10,
              shadowColor: colors.shadow,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        color: theme.accent,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackTheme {
  const _FeedbackTheme({required this.accent, required this.icon});

  final Color accent;
  final IconData icon;

  static _FeedbackTheme of(FeedbackKind kind) {
    switch (kind) {
      case FeedbackKind.success:
        return const _FeedbackTheme(
          accent: AppColors.success,
          icon: Icons.check_circle_rounded,
        );
      case FeedbackKind.danger:
        return const _FeedbackTheme(
          accent: AppColors.error,
          icon: Icons.error_rounded,
        );
      case FeedbackKind.info:
        return const _FeedbackTheme(
          accent: AppColors.primaryDark,
          icon: Icons.info_rounded,
        );
      case FeedbackKind.loading:
        return const _FeedbackTheme(
          accent: AppColors.primaryDark,
          icon: Icons.hourglass_top_rounded,
        );
    }
  }
}

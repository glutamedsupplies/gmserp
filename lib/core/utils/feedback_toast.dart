import 'package:flutter/material.dart';

import '../../widgets/feedback_card.dart';

export '../../widgets/feedback_card.dart' show FeedbackKind;

/// Centered interactive feedback overlays (success / danger / info / loading).
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

  /// Centered loading card (login, logout, long actions).
  /// [kind] tints the spinner: success=green, danger=red, info/loading=orange.
  static void showLoading(
    BuildContext context, {
    String title = 'Please wait',
    String message = 'Working…',
    FeedbackKind kind = FeedbackKind.loading,
  }) {
    hideLoading();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _loadingEntry = OverlayEntry(
      builder: (ctx) {
        return _CenteredFeedbackBarrier(
          absorbPointers: true,
          child: AppFeedbackCard(
            kind: kind,
            title: title,
            message: message,
            showSpinner: true,
          ),
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

  /// Centered confirm card. Returns `true` when the user confirms.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    FeedbackKind kind = FeedbackKind.info,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (ctx) {
        final palette = FeedbackPalette.of(kind);
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Material(
                color: Colors.transparent,
                child: AppFeedbackCard(
                  kind: kind,
                  title: title,
                  message: message,
                  actions: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(cancelLabel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return result == true;
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
        return _CenteredFeedbackBarrier(
          absorbPointers: false,
          onBarrierTap: () {
            if (_toastEntry == entry) hideToast();
          },
          child: _TimedFeedbackCard(
            key: ValueKey('feedback-$id'),
            kind: kind,
            title: title,
            message: message,
            duration: duration,
            onClose: () {
              if (_toastEntry == entry) hideToast();
            },
          ),
        );
      },
    );
    _toastEntry = entry;
    overlay.insert(entry);
  }
}

class _CenteredFeedbackBarrier extends StatelessWidget {
  const _CenteredFeedbackBarrier({
    required this.child,
    required this.absorbPointers,
    this.onBarrierTap,
  });

  final Widget child;
  final bool absorbPointers;
  final VoidCallback? onBarrierTap;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: child,
        ),
      ),
    );

    final stacked = Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBarrierTap,
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.38),
            ),
          ),
        ),
        content,
      ],
    );

    return Material(
      type: MaterialType.transparency,
      child: absorbPointers ? AbsorbPointer(child: stacked) : stacked,
    );
  }
}

class _TimedFeedbackCard extends StatefulWidget {
  const _TimedFeedbackCard({
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
  State<_TimedFeedbackCard> createState() => _TimedFeedbackCardState();
}

class _TimedFeedbackCardState extends State<_TimedFeedbackCard>
    with TickerProviderStateMixin {
  late final AnimationController _progress;
  late final AnimationController _appear;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..forward();
    _fade = CurvedAnimation(parent: _appear, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic),
    );

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
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            return AppFeedbackCard(
              kind: widget.kind,
              title: widget.title,
              message: widget.message,
              progress: 1 - _progress.value,
              onClose: widget.onClose,
            );
          },
        ),
      ),
    );
  }
}

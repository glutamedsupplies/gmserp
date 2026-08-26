import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';
import '../providers/settings_provider.dart';

/// Auth layout: centered form on phones; modern split + panel on web/desktop.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.showCard = true,
  });

  final Widget child;

  /// When false, the form sits directly on the background (no card chrome).
  final bool showCard;

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsProvider>();
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    final useSplit = Responsive.isWebOrDesktopShell &&
        width >= AppConstants.tabletBreakpoint;

    final form = showCard
        ? _AuthFormPanel(child: child)
        : ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppConstants.authFormMaxWidth,
            ),
            child: child,
          );

    if (useSplit) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Row(
          children: [
            const Expanded(flex: 5, child: _AuthBrandPanel()),
            Expanded(
              flex: 6,
              child: ColoredBox(
                color: showCard
                    ? colors.inputFill.withValues(alpha: 0.55)
                    : colors.background,
                child: SafeArea(
                  child: _AuthFormScroll(
                    bottomInset: bottomInset,
                    horizontal: 48,
                    verticalPad: 48,
                    child: form,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final horizontal = Responsive.horizontalPadding(context);
    final verticalPad = Responsive.isMobile(context) ? 28.0 : 40.0;
    final webShell = Responsive.isWebOrDesktopShell;

    return Scaffold(
      backgroundColor: colors.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          gradient: webShell && showCard
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.header.withValues(alpha: 0.55),
                    colors.background,
                    colors.inputFill.withValues(alpha: 0.65),
                  ],
                )
              : null,
        ),
        child: SafeArea(
          child: _AuthFormScroll(
            bottomInset: bottomInset,
            horizontal: horizontal,
            verticalPad: verticalPad,
            child: webShell || showCard
                ? form
                : ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppConstants.authFormMaxWidth,
                    ),
                    child: child,
                  ),
          ),
        ),
      ),
    );
  }
}

class _AuthFormScroll extends StatelessWidget {
  const _AuthFormScroll({
    required this.bottomInset,
    required this.horizontal,
    required this.verticalPad,
    required this.child,
  });

  final double bottomInset;
  final double horizontal;
  final double verticalPad;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minBodyHeight = (constraints.maxHeight -
                verticalPad * 2 -
                bottomInset)
            .clamp(0.0, double.infinity);

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            verticalPad,
            horizontal,
            verticalPad + bottomInset,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minBodyHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _AuthFormPanel extends StatelessWidget {
  const _AuthFormPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppConstants.authFormMaxWidth,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
          child: child,
        ),
      ),
    );
  }
}

class _AuthBrandPanel extends StatelessWidget {
  const _AuthBrandPanel();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.header,
            AppColors.primary.withValues(alpha: 0.42),
            colors.sidebar,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -48,
            top: -48,
            child: _BrandOrb(
              size: 220,
              color: AppColors.primary.withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            left: -36,
            bottom: 80,
            child: _BrandOrb(
              size: 160,
              color: AppColors.primaryDark.withValues(alpha: 0.18),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 48, 40, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/branding/gmserp_logo.png',
                        width: 52,
                        height: 52,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'GMSERP',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    'Run your team\nwith clarity.',
                    style: TextStyle(
                      fontSize: 40,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(
                      'Time cards, requests, and company workflows — '
                      'in one place built for how you already work.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: colors.sidebarMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _BrandChip(label: 'Attendance'),
                      _BrandChip(label: 'Approvals'),
                      _BrandChip(label: 'Companies'),
                    ],
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandOrb extends StatelessWidget {
  const _BrandOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _BrandChip extends StatelessWidget {
  const _BrandChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.card.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

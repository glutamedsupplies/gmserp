import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';
import 'compact_page.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final webShell = Responsive.isWebOrDesktopShell;
    return SizedBox(
      width: double.infinity,
      height: density.buttonHeight,
      child: ElevatedButton(
        onPressed: (isLoading || onPressed == null) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: webShell ? 0 : null,
          shadowColor: Colors.transparent,
          disabledBackgroundColor:
              isLoading ? AppColors.primary : null,
          disabledForegroundColor:
              isLoading ? AppColors.onPrimary : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isLoading
              ? Row(
                  key: const ValueKey('loading'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: density.compact ? 18 : 20,
                      height: density.compact ? 18 : 20,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      loadingLabel ?? label,
                      style: TextStyle(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: density.compact ? 15 : 17,
                      ),
                    ),
                  ],
                )
              : Text(
                  key: const ValueKey('label'),
                  label,
                ),
        ),
      ),
    );
  }
}

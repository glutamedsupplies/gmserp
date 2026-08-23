import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';

class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final horizontal = Responsive.horizontalPadding(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppConstants.authFormMaxWidth,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.of(context).card,
              borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.of(context).shadow,
                  blurRadius: isMobile ? 16 : 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(
                isMobile ? 24 : AppConstants.authCardPadding,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

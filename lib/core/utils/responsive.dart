import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

enum ScreenType { mobile, tablet, desktop }

class Responsive {
  Responsive._();

  static ScreenType screenType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppConstants.mobileBreakpoint) {
      return ScreenType.mobile;
    }
    if (width < AppConstants.tabletBreakpoint) {
      return ScreenType.tablet;
    }
    return ScreenType.desktop;
  }

  static bool isMobile(BuildContext context) =>
      screenType(context) == ScreenType.mobile;

  static bool isTablet(BuildContext context) =>
      screenType(context) == ScreenType.tablet;

  static bool isDesktop(BuildContext context) =>
      screenType(context) == ScreenType.desktop;

  static double horizontalPadding(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return AppConstants.mobileHorizontalPadding;
      case ScreenType.tablet:
        return 40;
      case ScreenType.desktop:
        return 48;
    }
  }
}

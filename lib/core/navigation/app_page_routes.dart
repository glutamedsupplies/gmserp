import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Overlay routes on web skip slide animation for snappier navigation.
PageRoute<T> signedInPageRoute<T>({
  required RouteSettings settings,
  required WidgetBuilder builder,
}) {
  if (kIsWeb) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  return MaterialPageRoute<T>(
    settings: settings,
    builder: builder,
  );
}

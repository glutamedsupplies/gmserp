import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_routes.dart';
import '../utils/platform_shell.dart';
import 'signed_in_nav_controller.dart';
import 'signed_in_router.dart';

/// Root of the signed-in area. On web, caches visited pages for fast switching.
class SignedInHost extends StatelessWidget {
  const SignedInHost({super.key});

  Widget _pageFor(SignedInNavController shell, String route) {
    return buildSignedInPage(
      RouteSettings(
        name: route,
        arguments: shell.argumentsFor(route),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<SignedInNavController>();
    final current = shell.current.name ?? AppRoutes.dashboard;

    if (!useSignedInPageCache) {
      return _pageFor(shell, current);
    }

    final visits = shell.visitOrder;
    final index = visits.indexOf(current);
    final safeIndex = index < 0 ? 0 : index;

    return IndexedStack(
      sizing: StackFit.expand,
      index: safeIndex.clamp(0, visits.length - 1),
      children: [
        for (final route in visits)
          TickerMode(
            enabled: route == current,
            child: _pageFor(shell, route),
          ),
      ],
    );
  }
}

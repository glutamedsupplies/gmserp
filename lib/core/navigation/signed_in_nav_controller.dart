import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_routes.dart';
import '../utils/platform_shell.dart';

/// Routes that open on top of the shell (detail / drill-down screens).
const signedInOverlayRoutes = <String>{
  AppRoutes.superAdminRoleDetails,
  AppRoutes.superAdminTaskDetails,
  AppRoutes.superAdminCompanyUsers,
};

bool isSignedInShellRoute(String? route) {
  if (route == null || route.isEmpty) return false;
  return !signedInOverlayRoutes.contains(route);
}

/// Keeps visited sidebar pages alive so switching tabs does not rebuild them.
class SignedInNavController extends ChangeNotifier {
  SignedInNavController({String initialRoute = AppRoutes.dashboard})
      : _current = RouteSettings(name: initialRoute);

  static const _maxCachedPages = 12;

  RouteSettings _current;
  final List<String> _visitOrder = [AppRoutes.dashboard];
  final Map<String, Object?> _argumentsByRoute = {};

  RouteSettings get current => _current;

  List<String> get visitOrder => List.unmodifiable(_visitOrder);

  Object? argumentsFor(String route) => _argumentsByRoute[route];

  void go(String route, {Object? arguments}) {
    if (!isSignedInShellRoute(route)) {
      return;
    }

    final sameRoute = _current.name == route;
    final sameArgs = _argumentsByRoute[route] == arguments;
    if (sameRoute && sameArgs) return;

    _argumentsByRoute[route] = arguments;
    if (useSignedInPageCache) {
      if (!_visitOrder.contains(route)) {
        _visitOrder.add(route);
        while (_visitOrder.length > _maxCachedPages) {
          final removed = _visitOrder.removeAt(1);
          _argumentsByRoute.remove(removed);
        }
      }
    } else {
      _visitOrder
        ..clear()
        ..add(route);
    }

    _current = RouteSettings(name: route, arguments: arguments);
    notifyListeners();
  }

  static SignedInNavController? maybeOf(BuildContext context) {
    try {
      return context.read<SignedInNavController>();
    } catch (_) {
      return null;
    }
  }

  /// Sidebar navigation: swap shell page first, then close any overlay route.
  static void goTo(
    BuildContext context,
    String route, {
    Object? arguments,
  }) {
    final navigator = Navigator.of(context);

    if (!isSignedInShellRoute(route)) {
      if (navigator.canPop()) {
        navigator.popUntil((r) => r.isFirst);
      }
      navigator.pushNamed(route, arguments: arguments);
      return;
    }

    final shell = maybeOf(context);
    shell?.go(route, arguments: arguments);

    if (navigator.canPop()) {
      navigator.popUntil((r) => r.isFirst);
    }
  }
}

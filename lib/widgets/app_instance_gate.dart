import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/close_browser_tab.dart';
import '../services/app_instance_guard.dart';

/// Blocks duplicate browser tabs. Desktop shells rely on native single-instance.
class AppInstanceGate extends StatefulWidget {
  const AppInstanceGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppInstanceGate> createState() => _AppInstanceGateState();
}

class _AppInstanceGateState extends State<AppInstanceGate> {
  late bool _isPrimary;
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    final guard = AppInstanceGuard.instance;
    _isPrimary = guard.isPrimary;
    _subscription = guard.onPrimaryChanged.listen((isPrimary) {
      if (!mounted) return;
      setState(() => _isPrimary = isPrimary);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPrimary) return widget.child;
    return const _DuplicateInstanceScreen();
  }
}

class _DuplicateInstanceScreen extends StatelessWidget {
  const _DuplicateInstanceScreen();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.tab_unselected_rounded,
                      size: 56,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${AppConstants.appName} is already open',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      kIsWeb
                          ? 'This app can only run in one browser tab at a time. '
                              'Close this tab and continue in your existing session.'
                          : 'This app is already running. Close the other window '
                              'and use that session instead.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                            height: 1.45,
                          ),
                    ),
                    if (kIsWeb) ...[
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: closeBrowserTab,
                        child: const Text('Close this tab'),
                      ),
                    ],
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

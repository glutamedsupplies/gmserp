import 'dart:async';

/// No-op guard for mobile and desktop shells that enforce single instance natively.
class AppInstanceGuard {
  AppInstanceGuard._();

  static final AppInstanceGuard instance = AppInstanceGuard._();

  bool get isPrimary => true;

  Stream<bool> get onPrimaryChanged => const Stream<bool>.empty();

  Future<void> initialize() async {}

  void dispose() {}
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import 'feedback_toast.dart';

/// App-wide feedback API. All cards are centered; colors are green / red / orange.
class SnackBarHelper {
  SnackBarHelper._();

  static void showSuccess(BuildContext context, String message) {
    FeedbackToast.showSuccess(context, message);
  }

  static void showError(BuildContext context, String message) {
    FeedbackToast.showDanger(context, message);
  }

  static void showInfo(BuildContext context, String message) {
    FeedbackToast.showInfo(context, message);
  }

  static void showLoading(
    BuildContext context, {
    String title = 'Please wait',
    String message = 'Working…',
    FeedbackKind kind = FeedbackKind.loading,
  }) {
    FeedbackToast.showLoading(
      context,
      title: title,
      message: message,
      kind: kind,
    );
  }

  static void hideLoading() {
    FeedbackToast.hideLoading();
  }

  /// Confirm (red) → spinner (red) → success (green). Returns `true` if signed out.
  static Future<bool> confirmLogout(
    BuildContext context, {
    bool clearCompanySelection = true,
    VoidCallback? onSignedOut,
  }) async {
    final confirmed = await FeedbackToast.confirm(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to continue.',
      confirmLabel: 'Sign out',
      cancelLabel: 'Cancel',
      kind: FeedbackKind.danger,
    );
    if (!confirmed || !context.mounted) return false;

    showLoading(
      context,
      title: 'Signing out',
      message: 'Ending your session…',
      kind: FeedbackKind.danger,
    );
    if (clearCompanySelection) {
      context.read<CompanyProvider>().clearSelection();
    }
    await context.read<AuthProvider>().logout();
    hideLoading();
    if (!context.mounted) return true;

    showSuccess(context, 'You have been signed out.');
    onSignedOut?.call();
    return true;
  }
}

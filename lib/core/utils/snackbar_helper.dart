import 'package:flutter/material.dart';

import 'feedback_toast.dart';

/// App-wide feedback API. Success / danger / info use interactive floating
/// cards; loading uses a spinner card overlay (login, logout, etc.).
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
  }) {
    FeedbackToast.showLoading(context, title: title, message: message);
  }

  static void hideLoading() {
    FeedbackToast.hideLoading();
  }
}

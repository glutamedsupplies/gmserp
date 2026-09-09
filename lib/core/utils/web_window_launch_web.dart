import 'dart:async';
import 'dart:html' as html;
import 'dart:math';

// Conditional import for Flutter web only (see web_window_launch.dart).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

bool _interactionHookInstalled = false;

void prepareWebWindowLaunch() {
  maximizeBrowserWindow();
  Timer(const Duration(milliseconds: 120), maximizeBrowserWindow);
  Timer(const Duration(milliseconds: 500), maximizeBrowserWindow);
  _installInteractionRetry();
}

void maximizeBrowserWindow() {
  try {
    final screen = html.window.screen;
    final width = screen?.width ?? html.window.outerWidth;
    final height = screen?.height ?? html.window.outerHeight;
    if (width <= 0 || height <= 0) return;

    html.window.moveTo(const Point(0, 0));
    html.window.resizeTo(width, height);
  } catch (_) {
    // Browsers may block resize for tabs not opened via script.
  }
}

void _installInteractionRetry() {
  if (_interactionHookInstalled) return;
  _interactionHookInstalled = true;

  void retry(html.Event _) {
    maximizeBrowserWindow();
    html.window.removeEventListener('pointerdown', retry);
    html.window.removeEventListener('keydown', retry);
  }

  html.window.addEventListener('pointerdown', retry);
  html.window.addEventListener('keydown', retry);
}

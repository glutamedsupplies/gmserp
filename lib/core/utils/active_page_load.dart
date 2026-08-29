import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Defers first load until this tab is visible in the web [IndexedStack] cache.
///
/// Cached routes stay mounted when you switch sidebar items. Without this,
/// every visited page would start heavy RTDB work as soon as it is built, even
/// while off-screen, which can freeze or error the web app.
mixin ActivePageLoad<T extends StatefulWidget> on State<T> {
  bool _didActivate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleActivateIfNeeded();
  }

  @override
  void activate() {
    super.activate();
    _scheduleActivateIfNeeded();
  }

  void _scheduleActivateIfNeeded() {
    if (_didActivate || !TickerMode.valuesOf(context).enabled) return;
    _didActivate = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!TickerMode.valuesOf(context).enabled) {
        _didActivate = false;
        return;
      }
      onPageActivated();
    });
  }

  /// Runs once when this page becomes the active sidebar tab.
  void onPageActivated();
}

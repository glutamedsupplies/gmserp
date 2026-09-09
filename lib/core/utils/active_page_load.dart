import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Defers first load until this tab is visible in the web [IndexedStack] cache.
///
/// Cached routes stay mounted when you switch sidebar items. Without this,
/// every visited page would start heavy RTDB work as soon as it is built, even
/// while off-screen, which can freeze or error the web app.
mixin ActivePageLoad<T extends StatefulWidget> on State<T> {
  bool _didActivate = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!mounted) return;
        _didActivate = false;
        _scheduleActivateIfNeeded();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

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
    if (!TickerMode.valuesOf(context).enabled) {
      _didActivate = false;
      return;
    }
    if (_didActivate) return;
    _didActivate = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!TickerMode.valuesOf(context).enabled) {
        _didActivate = false;
        return;
      }
      onPageActivated();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Reloads whenever this page becomes active or the app resumes.
  void onPageActivated();
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/rtdb/rtdb_service.dart';
import 'rtdb_platform.dart';
import 'realtime_refresh.dart';
export 'realtime_refresh.dart' show isRealtimeRefresh;

/// Refreshes the mounted page from database events without replacing its State
/// (and therefore without losing filters, scroll position, or form drafts).
mixin RealtimePage<T extends StatefulWidget> on State<T> {
  List<String> get realtimePaths;
  Future<void> refreshRealtimeData();
  Duration? get desktopRefreshInterval => null;
  @protected
  Stream<void> get realtimeChanges => RtdbService().watchChanges(realtimePaths);

  StreamSubscription<void>? _changes;
  Timer? _debounce;
  Timer? _poll;
  late final AppLifecycleListener _lifecycle;
  bool _visible = false;
  bool _running = false;
  bool _dirty = false;
  bool _background = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _background = false;
        if (mounted) _connect();
      },
      onHide: () {
        _background = true;
        _disconnect();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = context.watch<AuthProvider>().user?.id;
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (id == _userId && visible == _visible) return;
    _userId = id;
    _visible = visible;
    _disconnect();
    if (visible && id != null) _connect();
  }

  void _connect() {
    if (_background ||
        !_visible ||
        _userId == null ||
        _changes != null ||
        _poll != null) {
      return;
    }
    if (preferRtdbPolling) {
      final interval = desktopRefreshInterval;
      if (interval == null) return;
      _poll = Timer.periodic(interval, (_) {
        _dirty = true;
        unawaited(_refresh());
      });
      _dirty = true;
      _debounce = Timer(Duration.zero, () {
        _debounce = null;
        unawaited(_refresh());
      });
      return;
    }
    _changes = realtimeChanges.listen((_) {
      _dirty = true;
      _debounce ??= Timer(const Duration(milliseconds: 250), () {
        _debounce = null;
        unawaited(_refresh());
      });
    });
  }

  Future<void> _refresh() async {
    if (_running ||
        _background ||
        !_visible ||
        !mounted ||
        !_dirty ||
        _userId == null) {
      return;
    }
    _running = true;
    _dirty = false;
    try {
      RtdbService.clearReadCache();
      await runRealtimeRefresh(refreshRealtimeData);
    } catch (error, stack) {
      debugPrint('Realtime page refresh failed: $error\n$stack');
    } finally {
      _running = false;
      if (mounted && _dirty && _visible) {
        _debounce ??= Timer(const Duration(milliseconds: 250), () {
          _debounce = null;
          unawaited(_refresh());
        });
      }
    }
  }

  void _disconnect() {
    _poll?.cancel();
    _poll = null;
    unawaited(_changes?.cancel());
    _changes = null;
    _debounce?.cancel();
    _debounce = null;
    _dirty = false;
  }

  @override
  void dispose() {
    _disconnect();
    _lifecycle.dispose();
    super.dispose();
  }
}

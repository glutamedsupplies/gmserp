import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase Windows C++ SDK currently delivers database/auth events off the
/// Flutter platform thread, which can abort the process. Prefer polled `get()`
/// over long-lived `onValue` streams on Windows/Linux desktop.
bool get preferRtdbPolling {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
}

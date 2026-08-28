import 'package:flutter/foundation.dart' show kIsWeb;

/// Keep visited sidebar pages alive for instant switching (web only).
///
/// On Windows/Linux desktop, mounting multiple Firebase-backed pages at once
/// can trigger native `abort()` crashes in the Firebase C++ SDK.
bool get useSignedInPageCache => kIsWeb;

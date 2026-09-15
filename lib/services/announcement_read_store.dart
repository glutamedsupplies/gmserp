import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/firebase_data.dart';
import 'rtdb/rtdb_service.dart';
import 'notification_seen_store.dart';

/// Popup acknowledgements are separate from delivered notification alerts.
class AnnouncementReadStore {
  AnnouncementReadStore({RtdbService? rtdb}) : _rtdb = rtdb ?? RtdbService();
  final RtdbService _rtdb;
  Future<void> _writes = Future.value();
  String _key(String userId) => 'announcement_popup_read_$userId';

  Future<Set<String>> load(String userId) {
    final result = _writes.then((_) => _load(userId));
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Set<String>> _load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getStringList(_key(userId))?.toSet() ?? <String>{};
    final notificationSeen = await NotificationSeenStore.instance.loadSeen(
      userId,
    );
    local.addAll(
      notificationSeen
          .where((id) => id.startsWith('announce:'))
          .map((id) => id.substring('announce:'.length)),
    );
    try {
      final remote = await _rtdb.getChildren('announcementReads/$userId');
      final merged = {...local, ...remote.keys};
      await prefs.setStringList(_key(userId), merged.toList());
      local.addAll(merged);
      // Retry acknowledgements saved locally while offline.
      for (final id in merged.difference(remote.keys.toSet())) {
        await _rtdb.set('announcementReads/$userId/$id', {
          'readAt': serverTimestamp(),
        });
      }
      await prefs.setStringList(_key(userId), merged.toList());
      return merged;
    } catch (_) {
      return local;
    }
  }

  Future<void> markRead(String userId, String id) {
    final result = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_key(userId))?.toSet() ?? <String>{};
      ids.add(id);
      if (!await prefs.setStringList(_key(userId), ids.toList())) {
        throw StateError('Could not save announcement acknowledgement.');
      }
      try {
        await _rtdb.set('announcementReads/$userId/$id', {
          'readAt': serverTimestamp(),
        });
      } catch (_) {
        // Local acknowledgement prevents repeat popups; load retries syncing.
      }
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

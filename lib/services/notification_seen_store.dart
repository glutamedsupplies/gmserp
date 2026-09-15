import 'package:shared_preferences/shared_preferences.dart';

/// Persists which request-outcome notification cards a user has opened (seen).
class NotificationSeenStore {
  NotificationSeenStore._();
  static final NotificationSeenStore instance = NotificationSeenStore._();
  Future<void> _writes = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Atomically reserves an alert, including concurrent updates from listeners.
  Future<bool> claimAnnouncement(String userId, String entryId) =>
      _serialize(() async {
        final prefs = await SharedPreferences.getInstance();
        final seen = prefs.getStringList(_seenKey(userId)) ?? const <String>[];
        final announced =
            prefs.getStringList(_announcedKey(userId))?.toSet() ?? <String>{};
        if (seen.contains(entryId) || !announced.add(entryId)) return false;
        final saved = await prefs.setStringList(
          _announcedKey(userId),
          announced.toList(),
        );
        if (!saved) throw StateError('Could not save notification history.');
        return true;
      });

  static String _seenKey(String userId) => 'notif_seen_$userId';
  static String _announcedKey(String userId) => 'notif_announced_$userId';

  Future<Set<String>> loadSeen(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_seenKey(userId))?.toSet() ?? <String>{};
  }

  Future<void> markSeen(String userId, String entryId) async {
    await markSeenMany(userId, [entryId]);
  }

  Future<void> markSeenMany(String userId, Iterable<String> entryIds) =>
      _serialize(() async {
        final ids = entryIds.where((id) => id.isNotEmpty).toSet();
        if (ids.isEmpty) return;
        final prefs = await SharedPreferences.getInstance();
        final seen =
            prefs.getStringList(_seenKey(userId))?.toSet() ?? <String>{};
        final before = seen.length;
        seen.addAll(ids);
        if (seen.length == before) return;
        await prefs.setStringList(_seenKey(userId), seen.toList());
      });

  Future<Set<String>> loadAnnounced(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_announcedKey(userId))?.toSet() ?? <String>{};
  }

  Future<void> markAnnounced(String userId, String entryId) =>
      _serialize(() async {
        final prefs = await SharedPreferences.getInstance();
        final announced =
            prefs.getStringList(_announcedKey(userId))?.toSet() ?? <String>{};
        if (!announced.add(entryId)) return;
        await prefs.setStringList(_announcedKey(userId), announced.toList());
      });

  Future<void> clearUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_seenKey(userId));
    await prefs.remove(_announcedKey(userId));
  }
}

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../core/utils/firebase_data.dart';
import '../../core/utils/rtdb_platform.dart';
import '../../firebase_options.dart';
import 'rtdb_desktop_limiter.dart';

class _ChildrenCacheEntry {
  const _ChildrenCacheEntry(this.at, this.data);

  final DateTime at;
  final Map<String, Map<String, dynamic>> data;
}

class RtdbService {
  RtdbService({FirebaseDatabase? database})
      : _database = database ?? _defaultDatabase();

  final FirebaseDatabase _database;

  static final Map<String, _ChildrenCacheEntry> _childrenCache = {};
  static Duration get _childrenCacheTtl => preferRtdbPolling
      ? const Duration(seconds: 20)
      : const Duration(seconds: 5);


  static FirebaseDatabase _defaultDatabase() {
    final url = DefaultFirebaseOptions.currentPlatform.databaseURL;
    if (url == null || url.isEmpty) {
      return FirebaseDatabase.instance;
    }
    return FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: url,
    );
  }

  static void clearReadCache() => _childrenCache.clear();

  DatabaseReference ref(String path) => _database.ref(path);

  String newKey(String parentPath) {
    final key = ref(parentPath).push().key;
    if (key == null || key.isEmpty) {
      throw StateError('Unable to allocate Realtime Database key.');
    }
    return key;
  }

  Future<DataSnapshot> get(String path) =>
      RtdbDesktopLimiter.run(() => ref(path).get());

  Future<Map<String, dynamic>?> getMap(String path) async {
    final snapshot = await get(path);
    return snapshotMap(snapshot);
  }

  static Map<String, dynamic>? snapshotMap(DataSnapshot snapshot) {
    if (!snapshot.exists || snapshot.value == null) return null;
    final value = snapshot.value;
    if (value is Map) {
      return deepMap(value);
    }
    return null;
  }

  static Map<String, Map<String, dynamic>> snapshotChildren(
    DataSnapshot snapshot,
  ) {
    if (!snapshot.exists || snapshot.value == null) return {};
    return mapOrListChildrenDeep(snapshot.value);
  }

  /// Like [mapOrListChildren] but deep-converts nested maps.
  static Map<String, Map<String, dynamic>> mapOrListChildrenDeep(dynamic value) {
    final out = <String, Map<String, dynamic>>{};
    if (value is Map) {
      for (final entry in value.entries) {
        final child = entry.value;
        if (child is Map) {
          out[entry.key.toString()] = deepMap(child);
        }
      }
      return out;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final child = value[i];
        if (child is Map) {
          out['$i'] = deepMap(child);
        }
      }
    }
    return out;
  }

  /// Recursively converts RTDB nested maps to [Map<String, dynamic>].
  static Map<String, dynamic> deepMap(Map value) {
    final out = <String, dynamic>{};
    for (final entry in value.entries) {
      out[entry.key.toString()] = deepValue(entry.value);
    }
    return out;
  }

  static dynamic deepValue(dynamic value) {
    if (value is Map) return deepMap(value);
    if (value is List) return value.map(deepValue).toList();
    return value;
  }

  Future<Map<String, Map<String, dynamic>>> getChildren(String path) async {
    if (preferRtdbPolling) {
      final cached = _childrenCache[path];
      if (cached != null &&
          DateTime.now().difference(cached.at) < _childrenCacheTtl) {
        return cached.data;
      }
    }

    final snapshot = await get(path);
    final data = snapshotChildren(snapshot);
    if (preferRtdbPolling) {
      _childrenCache[path] = _ChildrenCacheEntry(DateTime.now(), data);
    }
    return data;
  }

  Future<void> set(String path, Map<String, dynamic> data) =>
      RtdbDesktopLimiter.run(() async {
        await ref(path).set(sanitizeForWrite(data));
        clearReadCache();
      });

  Future<void> merge(String path, Map<String, dynamic> data) =>
      RtdbDesktopLimiter.run(() async {
        await ref(path).update(sanitizeForWrite(data));
        clearReadCache();
      });

  Future<void> remove(String path) => RtdbDesktopLimiter.run(() async {
        await ref(path).remove();
        clearReadCache();
      });

  Stream<DatabaseEvent> onValue(String path) {
    if (preferRtdbPolling) {
      return Stream.error(
        UnsupportedError(
          'RTDB onValue is disabled on desktop. Use get() or getChildren().',
        ),
      );
    }
    return ref(path).onValue;
  }

  static Map<String, dynamic> sanitizeForWrite(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is DateTime) {
        out[entry.key] = writeFirebaseDate(value);
      } else if (value is Map) {
        out[entry.key] = sanitizeForWrite(Map<String, dynamic>.from(value));
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }
}

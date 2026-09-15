import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new_gmserp/services/announcement_read_store.dart';
import 'package:new_gmserp/services/rtdb/rtdb_service.dart';

class _Db implements RtdbService {
  bool offline = false;
  final rows = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, Map<String, dynamic>>> getChildren(String path) async {
    if (offline) throw StateError('Offline');
    return {
      for (final e in rows.entries)
        if (e.key.startsWith('$path/')) e.key.split('/').last: e.value,
    };
  }

  @override
  Future<void> set(String path, Map<String, dynamic> data) async {
    if (offline) throw StateError('Offline');
    rows[path] = data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'announcements already read in notifications are excluded from popups',
    () async {
      SharedPreferences.setMockInitialValues({
        'notif_seen_u': ['announce:a', 'clock:b'],
      });
      final db = _Db();
      expect(await AnnouncementReadStore(rtdb: db).load('u'), {'a'});
      expect(db.rows.containsKey('announcementReads/u/a'), isTrue);
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'acknowledgement survives reopening and stays isolated per user',
    () async {
      final db = _Db();
      await AnnouncementReadStore(rtdb: db).markRead('u', 'a');
      expect(await AnnouncementReadStore(rtdb: db).load('u'), {'a'});
      expect(await AnnouncementReadStore(rtdb: db).load('other'), isEmpty);
      SharedPreferences.setMockInitialValues({});
      expect(await AnnouncementReadStore(rtdb: db).load('u'), {'a'});
    },
  );
  test(
    'offline dismissal persists and syncs when connectivity returns',
    () async {
      final db = _Db()..offline = true;
      final store = AnnouncementReadStore(rtdb: db);
      await store.markRead('u', 'a');
      expect(await AnnouncementReadStore(rtdb: db).load('u'), {'a'});
      db.offline = false;
      expect(await store.load('u'), {'a'});
      expect(db.rows.containsKey('announcementReads/u/a'), isTrue);
    },
  );
}

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new_gmserp/models/activity_log_entry.dart';
import 'package:new_gmserp/models/user_model.dart';
import 'package:new_gmserp/models/user_role.dart';
import 'package:new_gmserp/providers/user_outcome_notifications_provider.dart';
import 'package:new_gmserp/services/notification_seen_store.dart';
import 'package:new_gmserp/services/notification_service.dart';
import 'package:new_gmserp/services/rtdb/rtdb_service.dart';

class _Database implements RtdbService {
  @override
  Stream<DatabaseEvent> onValue(String path) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications implements NotificationService {
  final shown = <String>[];
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> cancelRequestOutcome(String entryId) async {}
  @override
  Future<void> showRequestOutcome({
    required String entryId,
    required String title,
    required String body,
    bool alert = true,
  }) async {
    shown.add(entryId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'concurrent history writes preserve every entry and claim only once',
    () async {
      final store = NotificationSeenStore.instance;
      await Future.wait(
        List.generate(20, (i) => store.markSeen('a', 'seen:$i')),
      );
      expect(await store.loadSeen('a'), hasLength(20));
      final claims = await Future.wait(
        List.generate(20, (_) => store.claimAnnouncement('a', 'new')),
      );
      expect(claims.where((claimed) => claimed), hasLength(1));
      expect(await store.claimAnnouncement('a', 'seen:1'), isFalse);
      expect(await store.claimAnnouncement('b', 'new'), isTrue);
    },
  );

  test(
    'account switching does not repost delivered or seen outcomes',
    () async {
      final notifications = _Notifications();
      final provider = UserOutcomeNotificationsProvider(
        rtdb: _Database(),
        notifications: notifications,
      );
      addTearDown(provider.dispose);
      UserModel user(String id) => UserModel(
        id: id,
        username: id,
        email: '$id@test.com',
        phoneNumber: '',
        role: UserRole.superAdmin,
      );
      ActivityLogEntry entry(String id) => ActivityLogEntry(
        id: id,
        kind: ActivityLogKind.announcement,
        status: '',
        companyId: '',
        companyDocumentId: '',
        companyName: '',
        subjectName: '',
        subjectEmail: '',
        summary: 'Notice',
        detail: '',
        occurredAt: DateTime(2026),
      );
      final entries = [entry('announce:one'), entry('announce:two')];
      provider.syncUser(user('a'));
      await Future.wait([
        provider.applyPersonalActivityEntries(entries),
        provider.applyPersonalActivityEntries(entries),
      ]);
      expect(notifications.shown, hasLength(2));
      await provider.markSeen('announce:one');
      provider.syncUser(null);
      provider.syncUser(user('b'));
      await provider.applyPersonalActivityEntries(entries);
      expect(notifications.shown, hasLength(4));
      provider.syncUser(user('a'));
      await provider.applyPersonalActivityEntries(entries);
      expect(notifications.shown, hasLength(4));
      expect(provider.isSeen('announce:one'), isTrue);
      expect(provider.unseenCount, 1);
      await provider.applyPersonalActivityEntries([
        ...entries,
        entry('announce:three'),
      ]);
      expect(notifications.shown.last, 'announce:three');
      expect(notifications.shown, hasLength(5));
    },
  );
}

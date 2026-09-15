import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/services/announcement_repository.dart';
import 'package:new_gmserp/services/rtdb/rtdb_service.dart';

class _AnnouncementsDb implements RtdbService {
  @override
  Future<Map<String, Map<String, dynamic>>> getChildren(String path) async => {
    'everyone': {
      'companyId': 'company',
      'audience': 'everyone',
      'recipientIds': {'alice': true, 'bob': true},
      'subject': 'Meeting',
      'message': 'Please attend at 9 AM.',
      'actorName': 'Admin',
      'createdAt': 1789344000000,
    },
    'individual': {
      'companyId': 'company',
      'audience': 'specific',
      'recipientIds': {'alice': true},
      'subject': 'Schedule update',
      'message': 'Your shift starts at 10 AM.',
      'createdAt': 1789344060000,
    },
    'other': {
      'companyId': 'company',
      'audience': 'specific',
      'recipientIds': {'bob': true},
      'subject': 'Private',
    },
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'recipient sees group and individual announcements with full details',
    () async {
      final repository = AnnouncementRepository(rtdb: _AnnouncementsDb());
      final items = await repository.listForRecipient('alice');
      expect(items.map((item) => item.id), ['individual', 'everyone']);
      expect(items.last.subject, 'Meeting');
      expect(items.last.message, 'Please attend at 9 AM.');
      expect(items.last.actorName, 'Admin');
      expect(items.last.createdAt, isNotNull);
      expect(await repository.listForRecipient('unaddressed'), isEmpty);
    },
  );
}

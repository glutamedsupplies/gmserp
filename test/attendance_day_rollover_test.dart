import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/models/time_entry.dart';
import 'package:new_gmserp/providers/time_entry_provider.dart';
import 'package:new_gmserp/services/time_entry_repository.dart';
import 'package:new_gmserp/services/rtdb/rtdb_service.dart';

class MemoryRtdb implements RtdbService {
  final rows = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, Map<String, dynamic>>> getChildren(String path) async =>
      Map.of(rows);
  @override
  String newKey(String path) => 'entry${rows.length}';
  @override
  Future<void> set(String path, Map<String, dynamic> data) async {
    rows[path.split('/').last] = data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'approvals on separate days remain independent in either order',
    () async {
      for (final reverse in [false, true]) {
        final db = MemoryRtdb();
        final repo = TimeEntryRepository(rtdb: db);
        final today = DateTime.now();
        final yesterday = DateTime(today.year, today.month, today.day - 1, 9);
        final dates = reverse ? [today, yesterday] : [yesterday, today];
        for (final date in dates) {
          await repo.applyApprovedClockIn(
            userId: 'u',
            userEmail: '',
            username: '',
            companyId: 'c',
            companyDocumentId: 'c',
            companyName: '',
            workDate: formatWorkDate(date),
            timeIn: date,
          );
        }
        expect(db.rows.length, 2);
        final active = await repo.getOpenEntry(userId: 'u', companyId: 'c');
        expect(active!.workDate, formatWorkDate(today));
        expect(
          db.rows.values.every(
            (row) => row['timeOut'] == null && row['durationSeconds'] == null,
          ),
          isTrue,
        );
        await expectLater(
          repo.applyApprovedClockIn(
            userId: 'u',
            userEmail: '',
            username: '',
            companyId: 'c',
            companyDocumentId: 'c',
            companyName: '',
            workDate: formatWorkDate(today),
            timeIn: today,
          ),
          throwsStateError,
        );
      }
    },
  );

  test('missing time-out stops contributing hours after midnight', () {
    final start = DateTime(2026, 9, 13, 9);
    final entry = TimeEntry(
      id: 'e',
      userId: 'u',
      userEmail: '',
      username: '',
      companyId: 'c',
      companyDocumentId: 'c',
      companyName: '',
      status: TimeEntryStatus.open,
      timeIn: start,
      workDate: formatWorkDate(start),
    );
    expect(
      entryDuration(entry, DateTime(2026, 9, 13, 10)),
      const Duration(hours: 1),
    );
    final nextDay = DateTime(2026, 9, 14);
    expect(entryDuration(entry, nextDay), Duration.zero);
    expect(
      sumEntriesInRange([entry], DateTime(2026, 9, 1), nextDay, nextDay),
      Duration.zero,
    );
    expect(entry.timeOut, isNull);
  });
}

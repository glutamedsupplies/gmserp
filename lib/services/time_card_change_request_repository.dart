import '../core/utils/firebase_data.dart';
import '../models/company_model.dart';
import '../models/time_card_change_request.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';
import 'time_entry_repository.dart';

class TimeCardChangeRequestRepository {
  TimeCardChangeRequestRepository({
    RtdbService? rtdb,
    TimeEntryRepository? timeEntries,
  })  : _rtdb = rtdb ?? RtdbService(),
        _timeEntries = timeEntries ?? TimeEntryRepository();

  final RtdbService _rtdb;
  final TimeEntryRepository _timeEntries;

  static const String collectionName = RtdbPaths.timeCardChangeRequests;

  String _requestPath(String requestId) =>
      '${RtdbPaths.timeCardChangeRequests}/$requestId';

  Future<List<TimeCardChangeRequest>> _loadAll() async {
    final children = await _rtdb.getChildren(RtdbPaths.timeCardChangeRequests);
    return _sortedEntries(children.entries);
  }

  Future<List<TimeCardChangeRequest>> listAll() async {
    return _hydrateCurrents(await _loadAll());
  }

  Future<List<TimeCardChangeRequest>> listByRequester(String requesterId) async {
    final items = (await _loadAll())
        .where((request) => request.requesterId == requesterId)
        .toList();
    return _hydrateCurrents(items);
  }

  Future<List<TimeCardChangeRequest>> listByEmployeeId(String employeeId) async {
    final items = (await _loadAll())
        .where((request) => request.employeeId == employeeId)
        .toList();
    return _hydrateCurrents(items);
  }

  Stream<int> watchPendingCount() {
    return _rtdb.onValue(RtdbPaths.timeCardChangeRequests).map((event) {
      final children = RtdbService.snapshotChildren(event.snapshot);
      var count = 0;
      for (final data in children.values) {
        final status = data['status']?.toString().toLowerCase() ?? '';
        if (status == 'pending') count += 1;
      }
      return count;
    });
  }

  Future<TimeCardChangeRequest?> findPendingForWorkDate({
    required String employeeId,
    required String companyId,
    String? companyDocumentId,
    required String workDate,
  }) async {
    final docId = companyDocumentId?.trim() ?? '';
    for (final request in await _loadAll()) {
      if (request.employeeId != employeeId || !request.isPending) continue;
      if (request.workDate != workDate) continue;
      if (request.companyId == companyId ||
          (docId.isNotEmpty && request.companyDocumentId == docId) ||
          request.companyId.isEmpty) {
        return request;
      }
    }
    return null;
  }

  List<TimeCardChangeRequest> _sortedEntries(
    Iterable<MapEntry<String, Map<String, dynamic>>> entries,
  ) {
    final items = entries
        .map(
          (entry) => TimeCardChangeRequest.fromFirestore(
            id: entry.key,
            data: entry.value,
          ),
        )
        .toList();
    items.sort((a, b) {
      final byCreated = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (byCreated != 0) return byCreated;
      return b.workDate.compareTo(a.workDate);
    });
    return items;
  }

  Future<List<TimeCardChangeRequest>> _hydrateCurrents(
    List<TimeCardChangeRequest> items,
  ) async {
    final result = <TimeCardChangeRequest>[];
    for (final item in items) {
      if (item.hasPriorRecord || !item.isPending) {
        result.add(item);
        continue;
      }

      TimeEntry? entry;
      final entryId = item.existingEntryId;
      if (entryId != null && entryId.isNotEmpty) {
        entry = await _timeEntries.getById(entryId);
      }
      entry ??= await _timeEntries.findPriorEntry(
        userId: item.employeeId,
        companyId: item.companyId,
        companyDocumentId: item.companyDocumentId,
        workDate: item.workDate,
        entryId: item.existingEntryId,
      );

      if (entry == null) {
        result.add(item);
        continue;
      }

      result.add(
        item.copyWith(
          currentTimeIn: entry.timeIn,
          currentTimeOut: entry.timeOut,
          currentTimeInText: formatClockTime(entry.timeIn),
          currentTimeOutText: entry.timeOut == null
              ? 'Open'
              : formatClockTime(entry.timeOut!),
        ),
      );
    }
    return result;
  }

  Future<TimeCardChangeRequest> submit({
    required UserModel requester,
    required CompanyModel company,
    required String employeeId,
    required String employeeName,
    required String employeeEmail,
    required String workDate,
    required DateTime proposedTimeIn,
    DateTime? proposedTimeOut,
    DateTime? currentTimeIn,
    DateTime? currentTimeOut,
    String? existingEntryId,
    String note = '',
  }) async {
    if (proposedTimeOut != null && !proposedTimeOut.isAfter(proposedTimeIn)) {
      throw StateError('Time out must be after time in.');
    }

    final noteText = note.trim();
    final isSelfRequest = requester.id == employeeId;
    if (isSelfRequest && noteText.isEmpty) {
      throw StateError('A note is required for this request.');
    }

    final existingPending = await findPendingForWorkDate(
      employeeId: employeeId,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
      workDate: workDate,
    );
    if (existingPending != null) {
      throw StateError(
        'A change request for this employee on $workDate is already pending. '
        'Wait until it is approved or rejected before submitting again.',
      );
    }

    final prior = await _timeEntries.findPriorEntry(
      userId: employeeId,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
      workDate: workDate,
      entryId: existingEntryId,
    );

    final resolvedEntryId = prior?.id ?? existingEntryId;
    final resolvedTimeIn = prior?.timeIn ?? currentTimeIn;
    final resolvedTimeOut = prior != null ? prior.timeOut : currentTimeOut;

    final currentInLabel = resolvedTimeIn == null
        ? 'No prior record'
        : formatClockTime(resolvedTimeIn);
    final currentOutLabel = resolvedTimeOut == null
        ? (resolvedTimeIn == null ? 'No prior record' : 'Open')
        : formatClockTime(resolvedTimeOut);

    final id = _rtdb.newKey(RtdbPaths.timeCardChangeRequests);
    final data = <String, dynamic>{
      'type': 'timeEdit',
      'status': 'pending',
      'requesterId': requester.id,
      'requesterName': requester.username,
      'requesterEmail': requester.email,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'employeeEmail': employeeEmail,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'workDate': workDate,
      'proposedTimeIn': writeFirebaseDate(proposedTimeIn),
      'proposedTimeOut': proposedTimeOut == null
          ? null
          : writeFirebaseDate(proposedTimeOut),
      'currentTimeIn': resolvedTimeIn == null
          ? null
          : writeFirebaseDate(resolvedTimeIn),
      'currentTimeOut': resolvedTimeOut == null
          ? null
          : writeFirebaseDate(resolvedTimeOut),
      'currentTimeInLabel': currentInLabel,
      'currentTimeOutLabel': currentOutLabel,
      'existingEntryId': resolvedEntryId,
      'note': noteText,
      'createdAt': serverTimestamp(),
      'updatedAt': serverTimestamp(),
    };

    await _rtdb.set(_requestPath(id), data);
    return TimeCardChangeRequest.fromFirestore(id: id, data: data);
  }

  Future<void> reject(
    String requestId, {
    String reviewerId = '',
    String reviewerName = '',
  }) async {
    await _rtdb.merge(_requestPath(requestId), {
      'status': 'rejected',
      'updatedAt': serverTimestamp(),
      if (reviewerId.isNotEmpty) 'reviewedById': reviewerId,
      if (reviewerName.isNotEmpty) 'reviewedByName': reviewerName,
      'reviewedAt': serverTimestamp(),
    });
  }

  Future<void> approve(
    TimeCardChangeRequest request, {
    String reviewerId = '',
    String reviewerName = '',
  }) async {
    if (!request.isPending) {
      throw StateError('Only pending requests can be approved.');
    }

    final company = CompanyModel(
      id: request.companyId,
      documentId: request.companyDocumentId.isEmpty
          ? null
          : request.companyDocumentId,
      name: request.companyName,
      passwordHash: '',
      createdBy: '',
    );

    await _timeEntries.adminSaveEntry(
      entryId: request.existingEntryId,
      userId: request.employeeId,
      userEmail: request.employeeEmail,
      username: request.employeeName,
      company: company,
      timeIn: request.proposedTimeIn,
      timeOut: request.proposedTimeOut,
    );

    await _rtdb.merge(_requestPath(request.id), {
      'status': 'approved',
      'updatedAt': serverTimestamp(),
      if (reviewerId.isNotEmpty) 'reviewedById': reviewerId,
      if (reviewerName.isNotEmpty) 'reviewedByName': reviewerName,
      'reviewedAt': serverTimestamp(),
    });
  }

  /// Writes an approved audit row when Super Admin edits time in/out directly.
  Future<TimeCardChangeRequest> recordApprovedDirectEdit({
    required UserModel actor,
    required CompanyModel company,
    required String employeeId,
    required String employeeName,
    required String employeeEmail,
    required String workDate,
    required DateTime proposedTimeIn,
    DateTime? proposedTimeOut,
    DateTime? currentTimeIn,
    DateTime? currentTimeOut,
    String? existingEntryId,
  }) async {
    final currentInLabel = currentTimeIn == null
        ? 'No prior record'
        : formatClockTime(currentTimeIn);
    final currentOutLabel = currentTimeOut == null
        ? (currentTimeIn == null ? 'No prior record' : 'Open')
        : formatClockTime(currentTimeOut);

    final actorName =
        actor.username.trim().isNotEmpty ? actor.username.trim() : actor.email;
    final id = _rtdb.newKey(RtdbPaths.timeCardChangeRequests);
    final data = <String, dynamic>{
      'type': 'timeEdit',
      'status': 'approved',
      'source': 'directEdit',
      'requesterId': actor.id,
      'requesterName': actorName,
      'requesterEmail': actor.email,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'employeeEmail': employeeEmail,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'workDate': workDate,
      'proposedTimeIn': writeFirebaseDate(proposedTimeIn),
      'proposedTimeOut':
          proposedTimeOut == null ? null : writeFirebaseDate(proposedTimeOut),
      'currentTimeIn':
          currentTimeIn == null ? null : writeFirebaseDate(currentTimeIn),
      'currentTimeOut':
          currentTimeOut == null ? null : writeFirebaseDate(currentTimeOut),
      'currentTimeInLabel': currentInLabel,
      'currentTimeOutLabel': currentOutLabel,
      'existingEntryId': existingEntryId,
      'reviewedById': actor.id,
      'reviewedByName': actorName,
      'reviewedAt': serverTimestamp(),
      'createdAt': serverTimestamp(),
      'updatedAt': serverTimestamp(),
    };

    await _rtdb.set(_requestPath(id), data);
    return TimeCardChangeRequest.fromFirestore(id: id, data: data);
  }
}

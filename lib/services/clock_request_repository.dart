import '../core/utils/firebase_data.dart';
import '../models/clock_request.dart';
import '../models/company_model.dart';
import '../models/staff_assignment.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';
import 'company_repository.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';
import 'time_entry_repository.dart';

class ClockRequestRepository {
  ClockRequestRepository({
    RtdbService? rtdb,
    TimeEntryRepository? timeEntries,
    CompanyRepository? companies,
  })  : _rtdb = rtdb ?? RtdbService(),
        _timeEntries = timeEntries ?? TimeEntryRepository(),
        _companies = companies ?? CompanyRepository();

  final RtdbService _rtdb;
  final TimeEntryRepository _timeEntries;
  final CompanyRepository _companies;

  static const String collectionName = RtdbPaths.clockRequests;

  String _requestPath(String requestId) =>
      '${RtdbPaths.clockRequests}/$requestId';

  Future<List<ClockRequest>> _loadAll() async {
    final children = await _rtdb.getChildren(RtdbPaths.clockRequests);
    return _sortedEntries(children.entries);
  }

  Future<void> _ensureNotLocked({
    required String userId,
    required String companyId,
  }) async {
    final count = await _companies.getClockDeclineCount(
      companyId: companyId,
      userId: userId,
    );
    if (count >= StaffAssignment.clockDeclineLimit) {
      throw StateError(
        'Time in/out requests are locked after '
        '${StaffAssignment.clockDeclineLimit} declines. '
        'Ask an admin or super admin to edit your time card settings to unlock.',
      );
    }
  }

  String _requireNote(String? note) {
    final trimmed = note?.trim() ?? '';
    if (trimmed.isEmpty) {
      throw StateError('A note is required for this request.');
    }
    return trimmed;
  }

  Future<List<ClockRequest>> listAll() async => _loadAll();

  Future<List<ClockRequest>> listPending() async {
    return (await _loadAll()).where((request) => request.isPending).toList();
  }

  Future<List<ClockRequest>> listForUserCompany({
    required String userId,
    required String companyId,
    String? workDate,
  }) async {
    var items = (await _loadAll())
        .where(
          (request) =>
              request.userId == userId && request.companyId == companyId,
        )
        .toList();
    if (workDate != null && workDate.isNotEmpty) {
      items = items.where((request) => request.workDate == workDate).toList();
    }
    return items;
  }

  Future<List<ClockRequest>> listForUser(String userId) async {
    return (await _loadAll())
        .where((request) => request.userId == userId)
        .toList();
  }

  Future<ClockRequest?> findPendingClockIn({
    required String userId,
    required String companyId,
    required String workDate,
  }) async {
    final items = await listForUserCompany(
      userId: userId,
      companyId: companyId,
      workDate: workDate,
    );
    for (final item in items) {
      if (item.isPending && item.isClockIn) return item;
    }
    return null;
  }

  Future<ClockRequest?> findPendingClockOut({
    required String userId,
    required String companyId,
    required String workDate,
  }) async {
    final items = await listForUserCompany(
      userId: userId,
      companyId: companyId,
      workDate: workDate,
    );
    for (final item in items) {
      if (item.isPending && item.isClockOut) return item;
    }
    return null;
  }

  Future<ClockRequest> submitClockIn({
    required UserModel user,
    required CompanyModel company,
    required String note,
    DateTime? requestedAt,
  }) async {
    final at = requestedAt ?? DateTime.now();
    final workDate = formatWorkDate(at);
    final noteText = _requireNote(note);
    await _ensureNotLocked(userId: user.id, companyId: company.id);

    final open = await _timeEntries.getOpenEntry(
      userId: user.id,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
    );
    if (open != null) {
      throw StateError('You already have an open time entry.');
    }

    final today = await _timeEntries.getEntryForWorkDate(
      userId: user.id,
      companyId: company.id,
      workDate: workDate,
      companyDocumentId: company.firestoreId,
    );
    if (today != null) {
      throw StateError(
        'You already have a time card for today. '
        'Only one session is allowed per day.',
      );
    }

    final pendingIn = await findPendingClockIn(
      userId: user.id,
      companyId: company.id,
      workDate: workDate,
    );
    if (pendingIn != null) {
      throw StateError(
        'You already have a pending time-in request for today '
        '(${pendingIn.requestedAtLabel}).',
      );
    }

    final id = _rtdb.newKey(RtdbPaths.clockRequests);
    final data = <String, dynamic>{
      'type': ClockRequest.typeClockIn,
      'status': 'pending',
      'userId': user.id,
      'username': user.username,
      'userEmail': user.email,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'workDate': workDate,
      'requestedAt': writeFirebaseDate(at),
      'entryId': null,
      'note': noteText,
      'createdAt': serverTimestamp(),
      'updatedAt': serverTimestamp(),
    };

    await _rtdb.set(_requestPath(id), data);
    return ClockRequest.fromFirestore(id: id, data: data);
  }

  Future<ClockRequest> submitClockOut({
    required UserModel user,
    required CompanyModel company,
    required String note,
    String? entryId,
    DateTime? requestedAt,
  }) async {
    final at = requestedAt ?? DateTime.now();
    final workDate = formatWorkDate(at);
    final noteText = _requireNote(note);
    await _ensureNotLocked(userId: user.id, companyId: company.id);

    final pendingOut = await findPendingClockOut(
      userId: user.id,
      companyId: company.id,
      workDate: workDate,
    );
    if (pendingOut != null) {
      throw StateError(
        'You already have a pending time-out request '
        '(${pendingOut.requestedAtLabel}).',
      );
    }

    String? resolvedEntryId = entryId?.trim();
    String? relatedClockInId;

    if (resolvedEntryId != null && resolvedEntryId.isNotEmpty) {
      final entry = await _timeEntries.getById(resolvedEntryId);
      if (entry == null || !entry.isOpen) {
        throw StateError(
          'No open time entry to clock out. '
          'Submit time-in first, or wait if it was already closed.',
        );
      }
      if (entry.userId != user.id) {
        throw StateError('This time entry does not belong to you.');
      }
      if (!at.isAfter(entry.timeIn)) {
        throw StateError('Time out must be after your time in.');
      }
    } else {
      final open = await _timeEntries.getOpenEntry(
        userId: user.id,
        companyId: company.id,
        companyDocumentId: company.firestoreId,
      );
      if (open != null && open.workDate == workDate) {
        if (!at.isAfter(open.timeIn)) {
          throw StateError('Time out must be after your time in.');
        }
        resolvedEntryId = open.id;
      } else {
        final pendingIn = await findPendingClockIn(
          userId: user.id,
          companyId: company.id,
          workDate: workDate,
        );
        if (pendingIn == null) {
          throw StateError(
            'Submit a time-in request for today before timing out.',
          );
        }
        if (!at.isAfter(pendingIn.requestedAt)) {
          throw StateError(
            'Time out must be after your pending time in '
            '(${pendingIn.requestedAtLabel}).',
          );
        }
        relatedClockInId = pendingIn.id;
        resolvedEntryId = null;
      }
    }

    final id = _rtdb.newKey(RtdbPaths.clockRequests);
    final data = <String, dynamic>{
      'type': ClockRequest.typeClockOut,
      'status': 'pending',
      'userId': user.id,
      'username': user.username,
      'userEmail': user.email,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'workDate': workDate,
      'requestedAt': writeFirebaseDate(at),
      'entryId': resolvedEntryId,
      'relatedClockInId': relatedClockInId,
      'note': noteText,
      'createdAt': serverTimestamp(),
      'updatedAt': serverTimestamp(),
    };

    await _rtdb.set(_requestPath(id), data);
    return ClockRequest.fromFirestore(id: id, data: data);
  }

  Future<void> reject(
    ClockRequest request, {
    String reviewerId = '',
    String reviewerName = '',
  }) async {
    if (!request.isPending) {
      throw StateError('This request is no longer pending.');
    }

    final rejectFields = <String, dynamic>{
      'status': 'rejected',
      'updatedAt': serverTimestamp(),
      if (reviewerId.isNotEmpty) 'reviewedById': reviewerId,
      if (reviewerName.isNotEmpty) 'reviewedByName': reviewerName,
      'reviewedAt': serverTimestamp(),
    };

    await _rtdb.merge(_requestPath(request.id), rejectFields);

    await recordDeclineStrike(
      companyId: request.companyId,
      userId: request.userId,
    );

    if (!request.isClockIn) return;

    final pendingOut = await findPendingClockOut(
      userId: request.userId,
      companyId: request.companyId,
      workDate: request.workDate,
    );
    if (pendingOut == null) return;

    await _rtdb.merge(_requestPath(pendingOut.id), {
      ...rejectFields,
      'relatedClockInId': request.id,
      'rejectedWithClockInId': request.id,
    });
  }

  Future<void> recordDeclineStrike({
    required String companyId,
    required String userId,
  }) {
    return _companies.incrementClockDeclineCount(
      companyId: companyId,
      userId: userId,
    );
  }

  Future<void> unlockClockRequests({
    required String companyId,
    required String userId,
  }) {
    return _companies.resetClockDeclineCount(
      companyId: companyId,
      userId: userId,
    );
  }

  Map<String, dynamic> _reviewerUpdate({
    required String reviewerId,
    required String reviewerName,
  }) {
    return {
      'status': 'approved',
      'updatedAt': serverTimestamp(),
      if (reviewerId.isNotEmpty) 'reviewedById': reviewerId,
      if (reviewerName.isNotEmpty) 'reviewedByName': reviewerName,
      'reviewedAt': serverTimestamp(),
    };
  }

  Future<void> approve(
    ClockRequest request, {
    String reviewerId = '',
    String reviewerName = '',
  }) async {
    if (!request.isPending) {
      throw StateError('This request is no longer pending.');
    }

    final reviewFields = _reviewerUpdate(
      reviewerId: reviewerId,
      reviewerName: reviewerName,
    );

    if (request.isClockIn) {
      final entry = await _timeEntries.applyApprovedClockIn(
        userId: request.userId,
        userEmail: request.userEmail,
        username: request.username,
        companyId: request.companyId,
        companyDocumentId: request.companyDocumentId,
        companyName: request.companyName,
        workDate: request.workDate,
        timeIn: request.requestedAt,
      );
      await _rtdb.merge(_requestPath(request.id), reviewFields);

      final pendingOut = await findPendingClockOut(
        userId: request.userId,
        companyId: request.companyId,
        workDate: request.workDate,
      );
      if (pendingOut != null) {
        await _rtdb.merge(_requestPath(pendingOut.id), {
          'entryId': entry.id,
          'relatedClockInId': request.id,
          'updatedAt': serverTimestamp(),
        });
      }
      return;
    }

    final pendingIn = await findPendingClockIn(
      userId: request.userId,
      companyId: request.companyId,
      workDate: request.workDate,
    );
    if (pendingIn != null) {
      throw StateError(
        'Approve the time-in request for ${request.workDate} first, '
        'then approve this time-out.',
      );
    }

    var entryId = request.entryId?.trim() ?? '';
    if (entryId.isEmpty) {
      final open = await _timeEntries.getOpenEntry(
        userId: request.userId,
        companyId: request.companyId,
        companyDocumentId: request.companyDocumentId,
      );
      if (open != null && open.workDate == request.workDate) {
        entryId = open.id;
      }
    }

    if (entryId.isEmpty) {
      throw StateError(
        'Time in for ${request.workDate} is not approved yet. '
        'Approve time in before approving time out.',
      );
    }

    await _timeEntries.applyApprovedClockOut(
      entryId: entryId,
      timeOut: request.requestedAt,
    );
    await _rtdb.merge(_requestPath(request.id), {
      ...reviewFields,
      'entryId': entryId,
    });
  }

  List<ClockRequest> _sortedEntries(
    Iterable<MapEntry<String, Map<String, dynamic>>> entries,
  ) {
    final items = entries
        .map(
          (entry) =>
              ClockRequest.fromFirestore(id: entry.key, data: entry.value),
        )
        .toList();
    items.sort((a, b) {
      final byCreated = (b.createdAt ?? b.requestedAt)
          .compareTo(a.createdAt ?? a.requestedAt);
      if (byCreated != 0) return byCreated;
      return b.requestedAt.compareTo(a.requestedAt);
    });
    return items;
  }
}

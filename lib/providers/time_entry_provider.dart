import 'package:flutter/material.dart';

import '../models/clock_request.dart';
import '../models/company_model.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';
import '../services/clock_request_repository.dart';
import '../services/time_entry_repository.dart';

class TimeEntryProvider extends ChangeNotifier {
  TimeEntryProvider({
    TimeEntryRepository? repository,
    ClockRequestRepository? clockRequests,
  })  : _repository = repository ?? TimeEntryRepository(),
        _clockRequests = clockRequests ?? ClockRequestRepository();

  final TimeEntryRepository _repository;
  final ClockRequestRepository _clockRequests;

  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  TimeEntry? activeEntry;
  List<TimeEntry> todayEntries = [];
  List<TimeEntry> recentEntries = [];
  List<TimeEntry> allEntries = [];
  ClockRequest? pendingClockIn;
  ClockRequest? pendingClockOut;

  Duration get todayWorked => sumEntriesDuration(todayEntries);

  Duration get weekWorked =>
      sumEntriesInRange(allEntries, startOfWeek(DateTime.now()), DateTime.now());

  Duration get monthWorked =>
      sumEntriesInRange(allEntries, startOfMonth(DateTime.now()), DateTime.now());

  /// True when today already has a closed attendance session.
  bool get hasCompletedToday =>
      todayEntries.any((entry) => !entry.isOpen);

  /// True when the employee may submit a new time-in request for today.
  bool get canClockInToday =>
      activeEntry == null &&
      todayEntries.isEmpty &&
      pendingClockIn == null;

  /// True when the employee may submit a time-out request.
  /// Allowed with an approved open session, or a pending time-in for today.
  bool get canClockOutToday =>
      pendingClockOut == null &&
      (activeEntry != null || pendingClockIn != null);

  Future<void> loadForCompany({
    required UserModel user,
    required CompanyModel company,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final workDate = formatWorkDate(DateTime.now());
      final results = await Future.wait([
        _repository.getOpenEntry(userId: user.id, companyId: company.id),
        _repository.listForWorkDate(
          userId: user.id,
          companyId: company.id,
          workDate: workDate,
        ),
        _repository.listRecent(
          userId: user.id,
          companyId: company.id,
        ),
        _clockRequests.findPendingClockIn(
          userId: user.id,
          companyId: company.id,
          workDate: workDate,
        ),
        _clockRequests.findPendingClockOut(
          userId: user.id,
          companyId: company.id,
          workDate: workDate,
        ),
      ]);

      activeEntry = results[0] as TimeEntry?;
      todayEntries = results[1] as List<TimeEntry>;
      recentEntries = results[2] as List<TimeEntry>;
      pendingClockIn = results[3] as ClockRequest?;
      pendingClockOut = results[4] as ClockRequest?;
    } catch (_) {
      errorMessage = 'Unable to load time card records.';
      activeEntry = null;
      todayEntries = [];
      recentEntries = [];
      pendingClockIn = null;
      pendingClockOut = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    activeEntry = null;
    todayEntries = [];
    recentEntries = [];
    allEntries = [];
    pendingClockIn = null;
    pendingClockOut = null;
    errorMessage = null;
    isLoading = false;
    isSaving = false;
    notifyListeners();
  }

  Future<void> loadDetailsForCompany({
    required UserModel user,
    required CompanyModel company,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final workDate = formatWorkDate(DateTime.now());
      final results = await Future.wait([
        _repository.getOpenEntry(userId: user.id, companyId: company.id),
        _repository.listForWorkDate(
          userId: user.id,
          companyId: company.id,
          workDate: workDate,
        ),
        _repository.listAllForCompany(
          userId: user.id,
          companyId: company.id,
        ),
        _clockRequests.findPendingClockIn(
          userId: user.id,
          companyId: company.id,
          workDate: workDate,
        ),
        _clockRequests.findPendingClockOut(
          userId: user.id,
          companyId: company.id,
          workDate: workDate,
        ),
      ]);

      activeEntry = results[0] as TimeEntry?;
      todayEntries = results[1] as List<TimeEntry>;
      allEntries = results[2] as List<TimeEntry>;
      pendingClockIn = results[3] as ClockRequest?;
      pendingClockOut = results[4] as ClockRequest?;
      recentEntries = allEntries.length <= 12
          ? allEntries
          : allEntries.take(12).toList();
    } catch (_) {
      errorMessage = 'Unable to load time card records.';
      activeEntry = null;
      todayEntries = [];
      recentEntries = [];
      allEntries = [];
      pendingClockIn = null;
      pendingClockOut = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestClockIn({
    required UserModel user,
    required CompanyModel company,
    required String note,
  }) async {
    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      pendingClockIn = await _clockRequests.submitClockIn(
        user: user,
        company: company,
        note: note,
      );
      await _reloadLists(user: user, company: company);
      return true;
    } catch (error) {
      errorMessage = error is StateError
          ? error.message
          : 'Could not submit time-in request.';
      notifyListeners();
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> requestClockOut({
    required UserModel user,
    required CompanyModel company,
    required String note,
  }) async {
    if (!canClockOutToday) {
      errorMessage = pendingClockOut != null
          ? 'Your time-out request is already pending approval.'
          : 'Submit a time-in request for today before timing out.';
      notifyListeners();
      return false;
    }

    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      pendingClockOut = await _clockRequests.submitClockOut(
        user: user,
        company: company,
        note: note,
        entryId: activeEntry?.id,
      );
      await _reloadLists(user: user, company: company);
      return true;
    } catch (error) {
      errorMessage = error is StateError
          ? error.message
          : 'Could not submit time-out request.';
      notifyListeners();
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<void> _reloadLists({
    required UserModel user,
    required CompanyModel company,
  }) async {
    final workDate = formatWorkDate(DateTime.now());
    final results = await Future.wait([
      _repository.getOpenEntry(userId: user.id, companyId: company.id),
      _repository.listForWorkDate(
        userId: user.id,
        companyId: company.id,
        workDate: workDate,
      ),
      _repository.listRecent(
        userId: user.id,
        companyId: company.id,
      ),
      _clockRequests.findPendingClockIn(
        userId: user.id,
        companyId: company.id,
        workDate: workDate,
      ),
      _clockRequests.findPendingClockOut(
        userId: user.id,
        companyId: company.id,
        workDate: workDate,
      ),
    ]);
    activeEntry = results[0] as TimeEntry?;
    todayEntries = results[1] as List<TimeEntry>;
    recentEntries = results[2] as List<TimeEntry>;
    pendingClockIn = results[3] as ClockRequest?;
    pendingClockOut = results[4] as ClockRequest?;
  }
}

DateTime startOfWeek(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  return local.subtract(Duration(days: local.weekday - 1));
}

DateTime startOfMonth(DateTime date) {
  return DateTime(date.year, date.month);
}

Duration sumEntriesDuration(List<TimeEntry> entries, [DateTime? asOf]) {
  final now = asOf ?? DateTime.now();
  var total = Duration.zero;
  for (final entry in entries) {
    total += entryDuration(entry, now);
  }
  return total;
}

Duration sumEntriesInRange(
  List<TimeEntry> entries,
  DateTime rangeStart,
  DateTime rangeEnd, [
  DateTime? asOf,
]) {
  final now = asOf ?? DateTime.now();
  var total = Duration.zero;
  for (final entry in entries) {
    final entryEnd = entry.timeOut ?? now;
    if (entry.timeIn.isBefore(rangeEnd) && entryEnd.isAfter(rangeStart)) {
      final overlapStart =
          entry.timeIn.isAfter(rangeStart) ? entry.timeIn : rangeStart;
      final overlapEnd = entryEnd.isBefore(rangeEnd) ? entryEnd : rangeEnd;
      if (overlapEnd.isAfter(overlapStart)) {
        total += overlapEnd.difference(overlapStart);
      }
    }
  }
  return total;
}

Duration entryDuration(TimeEntry entry, DateTime asOf) {
  if (entry.isOpen) return asOf.difference(entry.timeIn);
  return entry.duration;
}

Map<String, List<TimeEntry>> groupEntriesByWorkDate(List<TimeEntry> entries) {
  final grouped = <String, List<TimeEntry>>{};
  for (final entry in entries) {
    grouped.putIfAbsent(entry.workDate, () => []).add(entry);
  }
  for (final list in grouped.values) {
    list.sort((a, b) => b.timeIn.compareTo(a.timeIn));
  }
  return grouped;
}

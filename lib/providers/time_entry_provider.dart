import 'package:flutter/material.dart';

import '../models/company_model.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';
import '../services/time_entry_repository.dart';

class TimeEntryProvider extends ChangeNotifier {
  TimeEntryProvider({TimeEntryRepository? repository})
      : _repository = repository ?? TimeEntryRepository();

  final TimeEntryRepository _repository;

  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  TimeEntry? activeEntry;
  List<TimeEntry> todayEntries = [];
  List<TimeEntry> recentEntries = [];
  List<TimeEntry> allEntries = [];

  Duration get todayWorked => sumEntriesDuration(todayEntries);

  Duration get weekWorked =>
      sumEntriesInRange(allEntries, startOfWeek(DateTime.now()), DateTime.now());

  Duration get monthWorked =>
      sumEntriesInRange(allEntries, startOfMonth(DateTime.now()), DateTime.now());

  /// True when today already has a closed attendance session.
  bool get hasCompletedToday =>
      todayEntries.any((entry) => !entry.isOpen);

  /// True when the employee may start a new time-in for today.
  bool get canClockInToday =>
      activeEntry == null && todayEntries.isEmpty;

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
      ]);

      activeEntry = results[0] as TimeEntry?;
      todayEntries = results[1] as List<TimeEntry>;
      recentEntries = results[2] as List<TimeEntry>;
    } catch (_) {
      errorMessage = 'Unable to load time card records.';
      activeEntry = null;
      todayEntries = [];
      recentEntries = [];
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
      ]);

      activeEntry = results[0] as TimeEntry?;
      todayEntries = results[1] as List<TimeEntry>;
      allEntries = results[2] as List<TimeEntry>;
      recentEntries = allEntries.length <= 12
          ? allEntries
          : allEntries.take(12).toList();
    } catch (_) {
      errorMessage = 'Unable to load time card records.';
      activeEntry = null;
      todayEntries = [];
      recentEntries = [];
      allEntries = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> clockIn({
    required UserModel user,
    required CompanyModel company,
  }) async {
    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      final entry = await _repository.clockIn(user: user, company: company);
      activeEntry = entry;
      await _reloadLists(user: user, company: company);
      return true;
    } catch (error) {
      errorMessage = error is StateError
          ? error.message
          : 'Could not record time in.';
      notifyListeners();
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> clockOut({
    required UserModel user,
    required CompanyModel company,
  }) async {
    final entry = activeEntry;
    if (entry == null) {
      errorMessage = 'You are not clocked in.';
      notifyListeners();
      return false;
    }

    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _repository.clockOut(entryId: entry.id);
      activeEntry = null;
      await _reloadLists(user: user, company: company);
      return true;
    } catch (error) {
      errorMessage = error is StateError
          ? error.message
          : 'Could not record time out.';
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
    ]);
    activeEntry = results[0] as TimeEntry?;
    todayEntries = results[1] as List<TimeEntry>;
    recentEntries = results[2] as List<TimeEntry>;
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

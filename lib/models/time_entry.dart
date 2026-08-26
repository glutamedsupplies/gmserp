enum TimeEntryStatus {
  open,
  closed;

  String get storageValue => name;

  static TimeEntryStatus fromStorage(String? value) {
    if (value == closed.storageValue) return closed;
    return open;
  }
}

class TimeEntry {
  final String id;
  final String userId;
  final String userEmail;
  final String username;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
  final TimeEntryStatus status;
  final DateTime timeIn;
  final DateTime? timeOut;
  final int? durationSeconds;
  final String workDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TimeEntry({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.username,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    required this.status,
    required this.timeIn,
    this.timeOut,
    this.durationSeconds,
    required this.workDate,
    this.createdAt,
    this.updatedAt,
  });

  bool get isOpen => status == TimeEntryStatus.open;

  Duration get duration {
    if (durationSeconds != null) {
      return Duration(seconds: durationSeconds!);
    }
    final end = timeOut ?? DateTime.now();
    return end.difference(timeIn);
  }

  factory TimeEntry.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return TimeEntry(
      id: id,
      userId: _string(data['userId']),
      userEmail: _string(data['userEmail']),
      username: _string(data['username']),
      companyId: _string(data['companyId']),
      companyDocumentId: _string(data['companyDocumentId']),
      companyName: _string(data['companyName']),
      status: TimeEntryStatus.fromStorage(data['status']?.toString()),
      timeIn: _parseDate(data['timeIn']) ?? DateTime.now(),
      timeOut: _parseDate(data['timeOut']),
      durationSeconds: _intOrNull(data['durationSeconds']),
      workDate: _string(data['workDate']),
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userEmail': userEmail,
      'username': username,
      'companyId': companyId,
      'companyDocumentId': companyDocumentId,
      'companyName': companyName,
      'status': status.storageValue,
      'timeIn': timeIn,
      'timeOut': timeOut,
      'durationSeconds': durationSeconds,
      'workDate': workDate,
    };
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}

String formatWorkDate(DateTime date) {
  final y = date.year;
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// 12-hour clock with AM/PM, e.g. `09:05:00 AM` or `09:05 AM`.
String formatClockTime(DateTime value, {bool withSeconds = true}) {
  return formatHourMinute12h(
    value.hour,
    value.minute,
    second: withSeconds ? value.second : null,
  );
}

/// 12-hour hour:minute (optional seconds) with AM/PM.
String formatHourMinute12h(
  int hour24,
  int minute, {
  int? second,
}) {
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final hour = hour12.toString().padLeft(2, '0');
  final min = minute.toString().padLeft(2, '0');
  if (second == null) {
    return '$hour:$min $period';
  }
  final sec = second.toString().padLeft(2, '0');
  return '$hour:$min:$sec $period';
}

/// Local date + 12-hour time, e.g. `2026-08-26 09:05 AM`.
String formatDateTime12h(DateTime value, {bool withSeconds = false}) {
  final local = value.toLocal();
  return '${formatWorkDate(local)} '
      '${formatClockTime(local, withSeconds: withSeconds)}';
}

/// Parses values like `09:00:00 AM` or `09:00 AM` onto [date].
DateTime? parseClockTimeOnDate(DateTime date, String value) {
  final raw = value.trim();
  if (raw.isEmpty ||
      raw == '—' ||
      raw == '-' ||
      raw.toLowerCase() == 'active' ||
      raw.toLowerCase() == 'open') {
    return null;
  }

  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) return null;

  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final second = int.parse(match.group(3) ?? '0');
  final period = match.group(4)!.toUpperCase();
  if (period == 'AM') {
    if (hour == 12) hour = 0;
  } else if (hour != 12) {
    hour += 12;
  }

  return DateTime(date.year, date.month, date.day, hour, minute, second);
}

String formatDuration(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m '
        '${seconds.toString().padLeft(2, '0')}s';
  }
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

String formatDurationShort(Duration value) {
  final totalMinutes = value.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  return '${minutes}m';
}

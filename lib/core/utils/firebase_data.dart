import 'package:firebase_database/firebase_database.dart';

/// Parses dates stored as Firestore timestamps, RTDB millis, or ISO strings.
DateTime? parseFirebaseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.round());
  }
  if (value is String) return DateTime.tryParse(value);
  try {
    return (value as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

int writeFirebaseDate(DateTime value) => value.millisecondsSinceEpoch;

Object serverTimestamp() => ServerValue.timestamp;

Object increment(num delta) => ServerValue.increment(delta);

Map<String, bool> recipientIdsToMap(List<String> ids) {
  final out = <String, bool>{};
  for (final id in ids) {
    final trimmed = id.trim();
    if (trimmed.isNotEmpty) out[trimmed] = true;
  }
  return out;
}

List<String> parseRecipientIds(dynamic value) {
  if (value is List) {
    return value
        .map((entry) => entry.toString())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }
  if (value is Map) {
    return value.keys
        .map((entry) => entry.toString())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }
  return const [];
}

/// RTDB/web often returns numbers as doubles (`9.0`); `int.tryParse('9.0')` fails.
int parseFirebaseInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.round();
  final text = value.toString().trim();
  if (text.isEmpty) return fallback;
  return int.tryParse(text) ?? double.tryParse(text)?.round() ?? fallback;
}

bool parseFirebaseBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

String parseFirebaseString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString().trim();
}

/// True when [storedCompanyId] / [storedDocumentId] match either candidate id.
bool matchesCompanyRef({
  required String? storedCompanyId,
  required String? storedDocumentId,
  String? companyId,
  String? companyDocumentId,
}) {
  final storedBiz = storedCompanyId?.trim() ?? '';
  final storedDoc = storedDocumentId?.trim() ?? '';
  final biz = companyId?.trim() ?? '';
  final doc = companyDocumentId?.trim() ?? '';

  bool hit(String needle) {
    if (needle.isEmpty) return false;
    return storedBiz == needle || storedDoc == needle;
  }

  return hit(biz) || hit(doc);
}

/// Converts RTDB map-or-array children into id → map entries (skips null holes).
Map<String, Map<String, dynamic>> mapOrListChildren(dynamic raw) {
  final out = <String, Map<String, dynamic>>{};
  if (raw is Map) {
    for (final entry in raw.entries) {
      final child = entry.value;
      if (child is Map) {
        out[entry.key.toString()] = Map<String, dynamic>.from(
          child.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    }
    return out;
  }
  if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      final child = raw[i];
      if (child is Map) {
        out['$i'] = Map<String, dynamic>.from(
          child.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    }
  }
  return out;
}

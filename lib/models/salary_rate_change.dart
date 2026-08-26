import 'package:cloud_firestore/cloud_firestore.dart';

/// Audit + inbox event when an admin/super admin changes a staff daily rate.
class SalaryRateChange {
  const SalaryRateChange({
    required this.id,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    required this.employeeId,
    required this.employeeName,
    required this.employeeEmail,
    required this.actorId,
    required this.actorName,
    required this.previousRate,
    required this.newRate,
    required this.recipientIds,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
  final String employeeId;
  final String employeeName;
  final String employeeEmail;
  final String actorId;
  final String actorName;
  final double previousRate;
  final double newRate;
  final List<String> recipientIds;
  final DateTime? createdAt;

  static String formatRate(double rate) {
    if (rate <= 0) return '₱0 / day';
    final whole = rate == rate.roundToDouble();
    final amount =
        whole ? rate.toStringAsFixed(0) : rate.toStringAsFixed(2);
    return '₱$amount / day';
  }

  String get rateChangeLabel =>
      '${formatRate(previousRate)} → ${formatRate(newRate)}';

  Map<String, dynamic> toFirestore() {
    return {
      'companyId': companyId,
      'companyDocumentId': companyDocumentId,
      'companyName': companyName,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'employeeEmail': employeeEmail,
      'actorId': actorId,
      'actorName': actorName,
      'previousRate': previousRate,
      'newRate': newRate,
      'recipientIds': recipientIds,
      'createdAt': FieldValue.serverTimestamp(),
      'type': 'salaryRate',
    };
  }

  factory SalaryRateChange.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    double asRate(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    DateTime? asDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      try {
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {
        return DateTime.tryParse(value.toString());
      }
    }

    final recipients = data['recipientIds'];
    return SalaryRateChange(
      id: id,
      companyId: data['companyId']?.toString() ?? '',
      companyDocumentId: data['companyDocumentId']?.toString() ?? '',
      companyName: data['companyName']?.toString() ?? '',
      employeeId: data['employeeId']?.toString() ?? '',
      employeeName: data['employeeName']?.toString() ?? '',
      employeeEmail: data['employeeEmail']?.toString() ?? '',
      actorId: data['actorId']?.toString() ?? '',
      actorName: data['actorName']?.toString() ?? '',
      previousRate: asRate(data['previousRate']),
      newRate: asRate(data['newRate']),
      recipientIds: recipients is List
          ? recipients.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
      createdAt: asDate(data['createdAt']),
    );
  }
}

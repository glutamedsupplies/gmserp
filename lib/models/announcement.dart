import 'package:cloud_firestore/cloud_firestore.dart';

enum AnnouncementAudience {
  companyAdmins,
  everyone,
  specific;

  String get storageValue => name;

  String get label {
    switch (this) {
      case AnnouncementAudience.companyAdmins:
        return 'Company admins';
      case AnnouncementAudience.everyone:
        return 'Everyone in company';
      case AnnouncementAudience.specific:
        return 'Specific members';
    }
  }

  static AnnouncementAudience fromStorage(String? value) {
    switch (value) {
      case 'companyAdmins':
        return AnnouncementAudience.companyAdmins;
      case 'specific':
        return AnnouncementAudience.specific;
      case 'everyone':
      default:
        return AnnouncementAudience.everyone;
    }
  }
}

class Announcement {
  const Announcement({
    required this.id,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    required this.audience,
    required this.recipientIds,
    required this.subject,
    required this.message,
    required this.actorId,
    required this.actorName,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
  final AnnouncementAudience audience;
  final List<String> recipientIds;
  final String subject;
  final String message;
  final String actorId;
  final String actorName;
  final DateTime? createdAt;

  Map<String, dynamic> toFirestore() {
    return {
      'type': 'announcement',
      'companyId': companyId,
      'companyDocumentId': companyDocumentId,
      'companyName': companyName,
      'audience': audience.storageValue,
      'recipientIds': recipientIds,
      'subject': subject.trim(),
      'message': message.trim(),
      'actorId': actorId,
      'actorName': actorName,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory Announcement.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
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
    return Announcement(
      id: id,
      companyId: data['companyId']?.toString() ?? '',
      companyDocumentId: data['companyDocumentId']?.toString() ?? '',
      companyName: data['companyName']?.toString() ?? '',
      audience: AnnouncementAudience.fromStorage(data['audience']?.toString()),
      recipientIds: recipients is List
          ? recipients
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
      subject: data['subject']?.toString().trim() ?? '',
      message: data['message']?.toString().trim() ?? '',
      actorId: data['actorId']?.toString() ?? '',
      actorName: data['actorName']?.toString() ?? '',
      createdAt: asDate(data['createdAt']),
    );
  }
}

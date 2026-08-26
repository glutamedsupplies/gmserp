import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/announcement.dart';

class AnnouncementRepository {
  AnnouncementRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'announcements';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionName);

  Future<Announcement> create({
    required String companyId,
    required String companyDocumentId,
    required String companyName,
    required AnnouncementAudience audience,
    required List<String> recipientIds,
    required String subject,
    required String message,
    required String actorId,
    required String actorName,
  }) async {
    final recipients =
        recipientIds.toSet().where((id) => id.isNotEmpty).toList()..sort();
    if (recipients.isEmpty) {
      throw StateError('Select at least one recipient.');
    }
    final trimmedSubject = subject.trim();
    final trimmedMessage = message.trim();
    if (trimmedSubject.isEmpty) {
      throw StateError('Subject is required.');
    }
    if (trimmedMessage.isEmpty) {
      throw StateError('Message is required.');
    }

    final ref = _collection.doc();
    final announcement = Announcement(
      id: ref.id,
      companyId: companyId,
      companyDocumentId: companyDocumentId,
      companyName: companyName,
      audience: audience,
      recipientIds: recipients,
      subject: trimmedSubject,
      message: trimmedMessage,
      actorId: actorId,
      actorName: actorName,
      createdAt: DateTime.now(),
    );
    await ref.set(announcement.toFirestore());
    return announcement;
  }

  Future<List<Announcement>> listAll() async {
    final snapshot = await _collection.get();
    final items = snapshot.docs
        .map((doc) => Announcement.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    items.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return items;
  }

  Future<List<Announcement>> listForRecipient(String userId) async {
    final snapshot = await _collection
        .where('recipientIds', arrayContains: userId)
        .get();
    final items = snapshot.docs
        .map((doc) => Announcement.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    items.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return items;
  }
}

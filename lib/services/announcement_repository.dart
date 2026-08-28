import '../models/announcement.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';

class AnnouncementRepository {
  AnnouncementRepository({RtdbService? rtdb}) : _rtdb = rtdb ?? RtdbService();

  final RtdbService _rtdb;

  static const String collectionName = RtdbPaths.announcements;

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

    final id = _rtdb.newKey(RtdbPaths.announcements);
    final announcement = Announcement(
      id: id,
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
    await _rtdb.set('${RtdbPaths.announcements}/$id', announcement.toFirestore());
    return announcement;
  }

  Future<List<Announcement>> listAll() async {
    final children = await _rtdb.getChildren(RtdbPaths.announcements);
    final items = children.entries
        .map(
          (entry) =>
              Announcement.fromFirestore(id: entry.key, data: entry.value),
        )
        .toList();
    items.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return items;
  }

  Future<List<Announcement>> listForRecipient(String userId) async {
    final items = await listAll();
    return items
        .where((item) => item.recipientIds.contains(userId))
        .toList();
  }
}

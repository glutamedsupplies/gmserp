import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/time_card_schedule.dart';

class TimeCardSettingsRepository {
  TimeCardSettingsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'timeCardSettings';
  static const String documentId = 'global';

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection(collectionName).doc(documentId);

  Future<TimeCardSchedule> load() async {
    final snapshot = await _doc.get();
    if (!snapshot.exists) return TimeCardSchedule.defaults;
    return TimeCardSchedule.fromFirestore(snapshot.data());
  }

  Future<void> save(TimeCardSchedule schedule) async {
    await _doc.set({
      ...schedule.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

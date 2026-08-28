import '../core/utils/firebase_data.dart';
import '../models/time_card_schedule.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';

class TimeCardSettingsRepository {
  TimeCardSettingsRepository({RtdbService? rtdb}) : _rtdb = rtdb ?? RtdbService();

  final RtdbService _rtdb;

  static const String collectionName = RtdbPaths.timeCardSettings;
  static const String documentId = 'global';

  String get _path => '${RtdbPaths.timeCardSettings}/$documentId';

  Future<TimeCardSchedule> load() async {
    final data = await _rtdb.getMap(_path);
    if (data == null) return TimeCardSchedule.defaults;
    return TimeCardSchedule.fromFirestore(data);
  }

  Future<void> save(TimeCardSchedule schedule) async {
    await _rtdb.merge(_path, {
      ...schedule.toFirestore(),
      'updatedAt': serverTimestamp(),
    });
  }
}

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/constants/app_constants.dart';
import '../models/app_release_config.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';

class AppReleaseRepository {
  AppReleaseRepository({RtdbService? rtdb}) : _rtdb = rtdb ?? RtdbService();

  final RtdbService _rtdb;

  static String platformDocumentId() {
    if (kIsWeb) return AppConstants.androidReleaseDocId;
    if (Platform.isIOS) return AppConstants.iosReleaseDocId;
    return AppConstants.androidReleaseDocId;
  }

  Future<AppReleaseConfig?> fetchCurrentPlatformRelease() async {
    final docId = platformDocumentId();
    final data = await _rtdb.getMap('${RtdbPaths.appConfig}/$docId');
    if (data == null || data.isEmpty) return null;

    final config = AppReleaseConfig.fromFirestore(data);
    if (config.latestBuildNumber <= 0 || config.downloadUrl.isEmpty) {
      return null;
    }
    return config;
  }
}

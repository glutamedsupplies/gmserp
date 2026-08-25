import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/constants/app_constants.dart';
import '../models/app_release_config.dart';

class AppReleaseRepository {
  AppReleaseRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String platformDocumentId() {
    if (kIsWeb) return AppConstants.androidReleaseDocId;
    if (Platform.isIOS) return AppConstants.iosReleaseDocId;
    return AppConstants.androidReleaseDocId;
  }

  Future<AppReleaseConfig?> fetchCurrentPlatformRelease() async {
    final docId = platformDocumentId();
    final snapshot = await _firestore
        .collection(AppConstants.appConfigCollection)
        .doc(docId)
        .get();
    if (!snapshot.exists) return null;

    final data = snapshot.data();
    if (data == null || data.isEmpty) return null;

    final config = AppReleaseConfig.fromFirestore(data);
    if (config.latestBuildNumber <= 0 || config.downloadUrl.isEmpty) {
      return null;
    }
    return config;
  }
}

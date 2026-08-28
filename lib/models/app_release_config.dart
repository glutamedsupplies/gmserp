import '../core/utils/firebase_data.dart';

/// Remote release info stored in Firestore (`appConfig/{android|ios}`).
class AppReleaseConfig {
  const AppReleaseConfig({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.downloadUrl,
    this.releaseNotes,
  });

  final String latestVersion;
  final int latestBuildNumber;
  final String downloadUrl;
  final String? releaseNotes;

  bool isNewerThanBuild(int installedBuildNumber) {
    return latestBuildNumber > installedBuildNumber;
  }

  factory AppReleaseConfig.fromFirestore(Map<String, dynamic> data) {
    return AppReleaseConfig(
      latestVersion: data['latestVersion']?.toString() ?? '0.0.0',
      latestBuildNumber: parseFirebaseInt(data['latestBuildNumber']),
      downloadUrl: data['downloadUrl']?.toString().trim() ?? '',
      releaseNotes: data['releaseNotes']?.toString().trim(),
    );
  }
}

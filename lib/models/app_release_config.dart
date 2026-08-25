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
      latestBuildNumber: _parseInt(data['latestBuildNumber']),
      downloadUrl: data['downloadUrl']?.toString().trim() ?? '',
      releaseNotes: data['releaseNotes']?.toString().trim(),
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }
}

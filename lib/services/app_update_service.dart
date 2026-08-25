import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:upgrader/upgrader.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../models/app_release_config.dart';
import 'app_release_repository.dart';

/// Checks Firestore release config first (works before Play Store), then
/// falls back to Google Play / App Store when listed.
class AppUpdateService {
  AppUpdateService._();

  static final AppReleaseRepository _releases = AppReleaseRepository();

  static Future<PackageInfo> packageInfo() => PackageInfo.fromPlatform();

  static Future<String> versionLabel() async {
    final info = await packageInfo();
    return '${info.version} (${info.buildNumber})';
  }

  static int _installedBuildNumber(PackageInfo info) {
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// Manual check from Settings.
  static Future<void> checkForUpdates(BuildContext context) async {
    if (!context.mounted) return;
    await _showLoading(context);

    try {
      final info = await packageInfo();
      final installedBuild = _installedBuildNumber(info);
      final installedLabel =
          info.version.isEmpty ? info.buildNumber : info.version;

      AppReleaseConfig? remote;
      try {
        remote = await _releases.fetchCurrentPlatformRelease();
      } catch (_) {
        remote = null;
      }

      if (remote != null && remote.isNewerThanBuild(installedBuild)) {
        if (!context.mounted) return;
        await _dismissLoading(context);
        if (!context.mounted) return;
        await _promptRemoteUpdate(
          context,
          remote: remote,
          installedLabel: installedLabel,
        );
        return;
      }

      final storeResult = await _checkPlayStore();
      if (!context.mounted) return;
      await _dismissLoading(context);
      if (!context.mounted) return;

      if (storeResult.status == _StoreCheckStatus.updateAvailable &&
          storeResult.upgrader != null) {
        await _promptStoreUpdate(
          context,
          upgrader: storeResult.upgrader!,
          installedLabel: installedLabel,
        );
        storeResult.upgrader!.dispose();
        return;
      }

      storeResult.upgrader?.dispose();

      if (remote != null) {
        if (!context.mounted) return;
        await _showMessageDialog(
          context,
          title: 'Up to date',
          message: installedLabel.isEmpty
              ? 'You already have the latest published build.'
              : 'Version $installedLabel is the latest published build.',
        );
        return;
      }

      if (storeResult.status == _StoreCheckStatus.upToDate) {
        if (!context.mounted) return;
        await _showMessageDialog(
          context,
          title: 'Up to date',
          message: installedLabel.isEmpty
              ? 'You already have the latest store version.'
              : 'Version $installedLabel is the latest store version.',
        );
        return;
      }

      if (!context.mounted) return;
      await _showMessageDialog(
        context,
        title: 'No update source yet',
        message:
            'No remote release is configured in Firestore and the app is not on the store yet.\n\n'
            'Ask a Super Admin to create `appConfig/${AppReleaseRepository.platformDocumentId()}` with '
            '`latestVersion`, `latestBuildNumber`, and `downloadUrl` (APK link from Firebase Storage).',
      );
    } catch (_) {
      if (!context.mounted) return;
      await _dismissLoading(context);
      if (!context.mounted) return;
      await _showMessageDialog(
        context,
        title: 'Could not check',
        message:
            'Unable to check for updates right now. Confirm you are online and try again.',
      );
    }
  }

  static Future<void> _promptRemoteUpdate(
    BuildContext context, {
    required AppReleaseConfig remote,
    required String installedLabel,
  }) async {
    final notes = remote.releaseNotes;
    final body = StringBuffer(
      'A newer build (${remote.latestVersion}) is available.\n'
      'You are on ${installedLabel.isEmpty ? 'an older build' : installedLabel}.',
    );
    if (notes != null && notes.isNotEmpty) {
      body.write('\n\n$notes');
    }

    final update = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update available'),
        content: Text(body.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (update != true) return;

    final uri = Uri.tryParse(remote.downloadUrl);
    if (uri == null) {
      if (!context.mounted) return;
      await _showMessageDialog(
        context,
        title: 'Invalid download link',
        message: 'The release download URL is not valid. Contact your administrator.',
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      await _showMessageDialog(
        context,
        title: 'Could not open link',
        message: 'Unable to open the download page. Try again or contact your administrator.',
      );
    }
  }

  static Future<void> _promptStoreUpdate(
    BuildContext context, {
    required Upgrader upgrader,
    required String installedLabel,
  }) async {
    final store = upgrader.currentAppStoreVersion ?? '';
    final update = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update available'),
        content: Text(
          'A newer version ($store) is on the store.\n'
          'You are on ${installedLabel.isEmpty ? 'an older build' : installedLabel}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (update == true) {
      await upgrader.sendUserToAppStore();
    }
  }

  static Future<_StoreCheckResult> _checkPlayStore() async {
    final upgrader = Upgrader(
      debugLogging: false,
      durationUntilAlertAgain: Duration.zero,
      countryCode: AppConstants.storeCountryCode,
      minAppVersion: '0.0.0',
      messages: UpgraderMessages(code: 'en'),
    );

    try {
      await upgrader.initialize();
      final store = upgrader.currentAppStoreVersion;
      if (store == null || store.isEmpty) {
        upgrader.dispose();
        return const _StoreCheckResult(_StoreCheckStatus.unavailable);
      }
      if (upgrader.isUpdateAvailable()) {
        return _StoreCheckResult(
          _StoreCheckStatus.updateAvailable,
          upgrader: upgrader,
        );
      }
      upgrader.dispose();
      return const _StoreCheckResult(_StoreCheckStatus.upToDate);
    } catch (_) {
      upgrader.dispose();
      return const _StoreCheckResult(_StoreCheckStatus.unavailable);
    }
  }

  static Future<void> _showLoading(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Checking for updates…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _dismissLoading(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  static Future<void> _showMessageDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

enum _StoreCheckStatus { updateAvailable, upToDate, unavailable }

class _StoreCheckResult {
  const _StoreCheckResult(this.status, {this.upgrader});

  final _StoreCheckStatus status;
  final Upgrader? upgrader;
}

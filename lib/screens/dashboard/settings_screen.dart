import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_routes.dart';
import '../../core/navigation/signed_in_nav_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pending_requests_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/app_update_service.dart';
import '../../services/firestore_to_rtdb_migration.dart';
import '../../services/notification_service.dart';
import '../../core/utils/feedback_toast.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final settings = context.watch<SettingsProvider>();
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);

    return DashboardScaffold(
      title: 'Settings',
      currentRoute: AppRoutes.settings,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: density.pagePadding,
            children: [
              CompactPageHeader(
                title: 'Settings',
                subtitle: 'Manage appearance, alerts, and your account.',
              ),
              SizedBox(height: density.sectionGap + 8),
              _SectionLabel('Appearance'),
              _SettingsCard(
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: settings.isDarkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      title: 'Dark mode',
                      subtitle: settings.isDarkMode
                          ? 'Using a dim green layout for low light'
                          : 'Using the light GMS theme',
                      value: settings.isDarkMode,
                      onChanged: settings.setDarkMode,
                    ),
                    Divider(height: 1, color: colors.border),
                    _SwitchRow(
                      icon: settings.isCompactMode
                          ? Icons.view_compact_rounded
                          : Icons.view_agenda_rounded,
                      title: 'Compact mode',
                      subtitle: settings.isCompactMode
                          ? 'Smaller fonts, tighter cards, denser chrome'
                          : 'Larger fonts, roomier cards, and spacing',
                      value: settings.isCompactMode,
                      onChanged: (value) async {
                        await settings.setCompactMode(value);
                        if (!context.mounted) return;
                        SnackBarHelper.showInfo(
                          context,
                          value
                              ? 'Compact mode turned on.'
                              : 'Normal mode turned on.',
                        );
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: density.sectionGap + 8),
              if (user?.role == UserRole.superAdmin ||
                  user?.role == UserRole.admin) ...[
                _SectionLabel('Preferences'),
                _SettingsCard(
                  child: _SwitchRow(
                    icon: Icons.notifications_rounded,
                    title: 'Notifications',
                    subtitle: settings.notificationsEnabled
                        ? 'Request alerts, sound, and app icon badge'
                        : 'Push alerts and app icon badge are off',
                    value: settings.notificationsEnabled,
                    onChanged: (value) async {
                      if (value) {
                        final allowed = await NotificationService.instance
                            .requestPermission();
                        if (!context.mounted) return;
                        if (!allowed) {
                          SnackBarHelper.showInfo(
                            context,
                            'Notification permission is required on this device.',
                          );
                        }
                      }
                      await settings.setNotificationsEnabled(value);
                      if (!context.mounted) return;
                      await context
                          .read<PendingRequestsProvider>()
                          .refreshNotificationPrefs();
                      if (!context.mounted) return;
                      SnackBarHelper.showInfo(
                        context,
                        value
                            ? 'Notifications turned on.'
                            : 'Notifications paused.',
                      );
                    },
                  ),
                ),
                SizedBox(height: density.sectionGap + 8),
              ],
              _SectionLabel('Account'),
              _SettingsCard(
                child: _NavRow(
                  icon: Icons.person_rounded,
                  title: 'Account',
                  subtitle: user?.email.isNotEmpty == true
                      ? user!.email
                      : 'Edit your profile details',
                  onTap: () {
                    SignedInNavController.goTo(context, AppRoutes.profile);
                  },
                ),
              ),
              SizedBox(height: density.sectionGap + 8),
              _SectionLabel('About'),
              _SettingsCard(
                child: Column(
                  children: [
                    const _AboutVersionRow(),
                    Divider(height: 1, color: colors.border),
                    _NavRow(
                      icon: Icons.system_update_rounded,
                      title: 'Check for updates',
                      subtitle:
                          'Checks Firebase release info, then Google Play / App Store',
                      onTap: () => AppUpdateService.checkForUpdates(context),
                    ),
                  ],
                ),
              ),
              if (user?.role == UserRole.superAdmin) ...[
                SizedBox(height: density.sectionGap + 8),
                _SectionLabel('Data migration'),
                _SettingsCard(
                  child: _NavRow(
                    icon: Icons.cloud_sync_rounded,
                    title: 'Copy Firestore → Realtime Database',
                    subtitle:
                        'One-time import of users, companies, time cards, and requests',
                    onTap: () => _runFirestoreMigration(context),
                  ),
                ),
              ],
              SizedBox(height: density.sectionGap),
              Text(
                'GMSERP keeps your theme and density on this device.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textHint,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _runFirestoreMigration(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Migrate Firestore data?'),
      content: const Text(
        'This copies existing Firestore data into Realtime Database. '
        'It does not delete Firestore. Safe to run once (or again to refresh).',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Migrate'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  FeedbackToast.showLoading(context, message: 'Copying Firestore → RTDB…');
  try {
    final summary = await FirestoreToRtdbMigration().run();
    if (!context.mounted) return;
    FeedbackToast.hideLoading();
    FeedbackToast.showSuccess(context, summary, title: 'Migration done');
  } catch (e) {
    if (!context.mounted) return;
    FeedbackToast.hideLoading();
    FeedbackToast.showDanger(
      context,
      e.toString(),
      title: 'Migration failed',
    );
  }
}

class _AboutVersionRow extends StatefulWidget {
  const _AboutVersionRow();

  @override
  State<_AboutVersionRow> createState() => _AboutVersionRowState();
}

class _AboutVersionRowState extends State<_AboutVersionRow> {
  late Future<String> _versionLabel;

  @override
  void initState() {
    super.initState();
    _versionLabel = AppUpdateService.versionLabel();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _versionLabel,
      builder: (context, snapshot) {
        final version = snapshot.data ?? '…';
        return _NavRow(
          icon: Icons.info_outline_rounded,
          title: AppConstants.appName,
          subtitle: snapshot.hasError
              ? 'Version unavailable'
              : 'Version $version',
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 4,
        bottom: density.compact ? 6 : 10,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: density.chipLabelSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: AppColors.of(context).textSecondary,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    return Material(
      color: AppColors.of(context).inputFill,
      borderRadius: BorderRadius.circular(density.settingsCardRadius),
      child: child,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: density.settingsRowPadding,
      child: Row(
        children: [
          _IconBadge(icon: icon),
          SizedBox(width: density.compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: density.cardTitleSize,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                ),
                SizedBox(height: density.titleSubtitleGap),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: density.captionSize,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(density.settingsCardRadius),
      child: Padding(
        padding: density.compact
            ? const EdgeInsets.all(12)
            : const EdgeInsets.all(16),
        child: Row(
          children: [
            _IconBadge(icon: icon),
            SizedBox(width: density.compact ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: density.cardTitleSize,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                  ),
                  SizedBox(height: density.titleSubtitleGap),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: density.captionSize,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final size = density.settingsIconSize;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(density.radius),
      ),
      child: Icon(
        icon,
        size: density.compact ? 20 : 24,
        color: AppColors.of(context).textPrimary,
      ),
    );
  }
}

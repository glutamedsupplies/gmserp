import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/dashboard_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final settings = context.watch<SettingsProvider>();
    final colors = AppColors.of(context);

    return DashboardScaffold(
      title: 'Settings',
      currentRoute: AppRoutes.settings,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Manage appearance, alerts, and your account.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              const _SectionLabel('Appearance'),
              _SettingsCard(
                child: _SwitchRow(
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
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Preferences'),
              _SettingsCard(
                child: _SwitchRow(
                  icon: Icons.notifications_rounded,
                  title: 'Notifications',
                  subtitle: settings.notificationsEnabled
                      ? 'Alerts for account and company updates'
                      : 'All in-app alerts are paused',
                  value: settings.notificationsEnabled,
                  onChanged: (value) {
                    settings.setNotificationsEnabled(value);
                    SnackBarHelper.showInfo(
                      context,
                      value
                          ? 'Notifications turned on.'
                          : 'Notifications paused.',
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Account'),
              _SettingsCard(
                child: _NavRow(
                  icon: Icons.person_rounded,
                  title: 'Account',
                  subtitle: user?.email.isNotEmpty == true
                      ? user!.email
                      : 'Edit your profile details',
                  onTap: () {
                    Navigator.of(context).pushReplacementNamed(
                      AppRoutes.profile,
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('About'),
              _SettingsCard(
                child: _NavRow(
                  icon: Icons.info_outline_rounded,
                  title: AppConstants.appName,
                  subtitle: 'Version 0.1.0',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'GMSERP keeps your theme on this device.',
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
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
    return Material(
      color: AppColors.of(context).inputFill,
      borderRadius: BorderRadius.circular(18),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(
        children: [
          _IconBadge(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.of(context).textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(context).textSecondary,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _IconBadge(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
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
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.of(context).textPrimary),
    );
  }
}

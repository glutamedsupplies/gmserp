import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/app_routes.dart';
import '../core/navigation/sidebar_destinations.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/snackbar_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/company_provider.dart';
import 'user_avatar.dart';

class DashboardScaffold extends StatefulWidget {
  const DashboardScaffold({
    super.key,
    required this.title,
    required this.currentRoute,
    required this.child,
    this.actions,
  });

  final String title;
  final String currentRoute;
  final Widget child;
  final List<Widget>? actions;

  @override
  State<DashboardScaffold> createState() => _DashboardScaffoldState();
}

class _DashboardScaffoldState extends State<DashboardScaffold> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _sidebarExpanded = true;

  Future<void> _logout() async {
    context.read<CompanyProvider>().clearSelection();
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    SnackBarHelper.showInfo(context, 'You have been signed out.');
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.login,
      (route) => false,
    );
  }

  void _goTo(String route) {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
    if (route == widget.currentRoute) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  void _toggleNav() {
    final wide = MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;
    if (wide) {
      setState(() => _sidebarExpanded = !_sidebarExpanded);
    } else {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold?.isDrawerOpen == true) {
        Navigator.of(context).pop();
      } else {
        scaffold?.openDrawer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;
    final user = context.watch<AuthProvider>().user;
    final destinations = destinationsForRole(user?.role);

    final sidebar = _AppSidebar(
      expanded: !wide || _sidebarExpanded,
      currentRoute: widget.currentRoute,
      destinations: destinations,
      onSelect: _goTo,
      onLogout: _logout,
      onProfile: () => _goTo(AppRoutes.profile),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: wide
          ? null
          : Drawer(
              backgroundColor: AppColors.sidebar,
              child: SafeArea(child: sidebar),
            ),
      body: Column(
        children: [
          _DashboardHeader(
            title: widget.title,
            onMenuPressed: _toggleNav,
            actions: widget.actions,
          ),
          Expanded(
            child: Row(
              children: [
                if (wide)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: _sidebarExpanded ? 268 : 84,
                    color: AppColors.sidebar,
                    child: sidebar,
                  ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.title,
    required this.onMenuPressed,
    this.actions,
  });

  final String title;
  final VoidCallback onMenuPressed;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final company = context.watch<CompanyProvider>().selectedCompany;

    return Material(
      color: AppColors.background,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Menu',
                    onPressed: onMenuPressed,
                    icon: const Icon(Icons.menu_rounded),
                    color: AppColors.textPrimary,
                  ),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Image.asset('assets/branding/gmserp_logo.jpg'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (company != null)
                          Text(
                            company.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ...?actions,
                  if (user != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        user.role.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(height: 4, color: AppColors.headerAccent),
        ],
      ),
    );
  }
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({
    required this.expanded,
    required this.currentRoute,
    required this.destinations,
    required this.onSelect,
    required this.onLogout,
    required this.onProfile,
  });

  final bool expanded;
  final String currentRoute;
  final List<SidebarDestination> destinations;
  final ValueChanged<String> onSelect;
  final VoidCallback onLogout;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final selected = currentRoute == AppRoutes.profile;

    return ColoredBox(
      color: AppColors.sidebar,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              expanded ? 10 : 8,
              12,
              expanded ? 10 : 8,
              8,
            ),
            child: Material(
              color: selected ? AppColors.sidebarSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onProfile,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    expanded ? 8 : 4,
                    10,
                    expanded ? 8 : 4,
                    10,
                  ),
                  child: expanded
                      ? Row(
                          children: [
                            UserAvatar(
                              key: ValueKey(auth.avatarRevision),
                              bytes: auth.avatarBytes,
                              name: user?.username ?? user?.email ?? '',
                              size: 44,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'GMSERP',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    user?.username.isNotEmpty == true
                                        ? user!.username
                                        : 'Account',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (user?.email.isNotEmpty == true)
                                    Text(
                                      user!.email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Tooltip(
                            message: user?.username ?? 'Edit profile',
                            child: UserAvatar(
                              key: ValueKey(auth.avatarRevision),
                              bytes: auth.avatarBytes,
                              name: user?.username ?? user?.email ?? '',
                              size: 40,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: AppColors.border, height: 24),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final item in destinations)
                  _NavTile(
                    expanded: expanded,
                    selected: item.route == currentRoute,
                    icon: item.icon,
                    label: item.label,
                    onTap: () => onSelect(item.route),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: AppColors.border, height: 16),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
            child: _NavTile(
              expanded: expanded,
              selected: false,
              icon: Icons.logout_rounded,
              label: 'Logout',
              foreground: AppColors.error,
              onTap: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.expanded,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.foreground,
  });

  final bool expanded;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final color = foreground ?? AppColors.textPrimary;
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 0,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment:
                  expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (expanded) return tile;
    return Tooltip(message: label, child: tile);
  }
}

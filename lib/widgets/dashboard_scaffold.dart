import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/app_routes.dart';
import '../core/navigation/app_navigator.dart';
import '../core/navigation/sidebar_destinations.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/snackbar_helper.dart';
import '../models/user_role.dart';
import '../providers/auth_provider.dart';
import '../providers/company_provider.dart';
import '../providers/pending_requests_provider.dart';
import '../providers/settings_provider.dart';
import 'pending_count_badge.dart';
import 'user_avatar.dart';

WidgetStateProperty<Color?> _sidebarOverlayColor(AppColors colors) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) {
      return colors.textPrimary.withValues(alpha: 0.10);
    }
    if (states.contains(WidgetState.focused)) {
      return colors.sidebarSelected.withValues(alpha: 0.85);
    }
    if (states.contains(WidgetState.hovered)) {
      return AppColors.primary.withValues(alpha: 0.12);
    }
    return Colors.transparent;
  });
}

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
  bool _sidebarExpanded = true;
  bool _redirectScheduled = false;

  Future<void> _logout() async {
    context.read<CompanyProvider>().clearSelection();
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    SnackBarHelper.showInfo(context, 'You have been signed out.');
  }

  void _goTo(String route) {
    if (AppNavigator.isSessionRoute(route)) {
      final companies = context.read<CompanyProvider>();
      if (route == AppRoutes.selectCompany) {
        companies.beginCompanyPick();
        return;
      }
      companies.endCompanyPick();
      AppNavigator.popToRoot(context);
      return;
    }
    if (route == widget.currentRoute) return;
    final user = context.read<AuthProvider>().user;
    if (!_canOpenRoute(user?.role, route)) return;
    if (widget.currentRoute.startsWith('$route/')) {
      Navigator.of(context).pop();
      return;
    }
    if (ModalRoute.of(context)?.isFirst ?? true) {
      Navigator.of(context).pushNamed(route);
    } else {
      Navigator.of(context).pushReplacementNamed(route);
    }
  }

  void _redirectIfCompanyRequired() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    if (user.role != UserRole.employee && user.role != UserRole.admin) {
      return;
    }
    if (widget.currentRoute == AppRoutes.selectCompany) return;
    if (context.read<CompanyProvider>().selectedCompany != null) return;
    AppNavigator.popToRoot(context);
  }

  bool _canOpenRoute(UserRole? role, String route) {
    const superAdminOnly = {
      AppRoutes.superAdmin,
      AppRoutes.superAdminCreate,
      AppRoutes.superAdminList,
      AppRoutes.superAdminCompanyUsers,
      AppRoutes.superAdminEmployees,
      AppRoutes.superAdminRoles,
      AppRoutes.superAdminRoleDetails,
      AppRoutes.superAdminTasks,
      AppRoutes.superAdminTaskDetails,
      AppRoutes.superAdminUsers,
      AppRoutes.superAdminRequests,
    };
    if (superAdminOnly.contains(route)) {
      return role == UserRole.superAdmin;
    }
    if (route == AppRoutes.adminDashboard ||
        route == AppRoutes.adminSubmittedRequests ||
        route == AppRoutes.superAdminTimeCardDetails ||
        route == AppRoutes.superAdminTimeCardSettings ||
        route == AppRoutes.superAdminEditTimeCard) {
      return role == UserRole.admin || role == UserRole.superAdmin;
    }
    const employeeTimeCardRoutes = {
      AppRoutes.employeeTimeInOut,
      AppRoutes.employeeTimeCardDetails,
      AppRoutes.employeeRequestLeave,
    };
    if (employeeTimeCardRoutes.contains(route)) {
      return role == UserRole.employee;
    }
    return true;
  }

  void _toggleNav(BuildContext scaffoldContext) {
    final wide = MediaQuery.sizeOf(scaffoldContext).width >=
        AppConstants.tabletBreakpoint;
    if (wide) {
      setState(() => _sidebarExpanded = !_sidebarExpanded);
    } else {
      final scaffold = Scaffold.of(scaffoldContext);
      if (scaffold.isDrawerOpen) {
        Navigator.of(scaffoldContext).pop();
      } else {
        scaffold.openDrawer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;
    final user = context.watch<AuthProvider>().user;
    final selectedCompany = context.watch<CompanyProvider>().selectedCompany;
    final destinations = destinationsForRole(user?.role);
    final colors = AppColors.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PendingRequestsProvider>().syncUser(
            context.read<AuthProvider>().user,
          );
    });
    // Re-apply badge prefs when the notifications toggle changes.
    context.watch<SettingsProvider>();
    final pendingCount =
        context.watch<PendingRequestsProvider>().pendingCount;
    final needsCompany = (user?.role == UserRole.employee ||
            user?.role == UserRole.admin) &&
        selectedCompany == null &&
        widget.currentRoute != AppRoutes.selectCompany;
    if (needsCompany && !_redirectScheduled) {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _redirectIfCompanyRequired();
      });
    } else if (!needsCompany) {
      _redirectScheduled = false;
    }

    final sidebar = Theme(
      data: Theme.of(context).copyWith(
        splashColor: colors.textPrimary.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        focusColor: colors.sidebarSelected,
        hoverColor: AppColors.primary.withValues(alpha: 0.10),
      ),
      child: _AppSidebar(
        expanded: !wide || _sidebarExpanded,
        currentRoute: widget.currentRoute,
        destinations: destinations,
        pendingSubmittedCount: pendingCount,
        onSelect: _goTo,
        onLogout: _logout,
        onProfile: () => _goTo(AppRoutes.profile),
      ),
    );

    return Scaffold(
      backgroundColor: colors.background,
      drawer: wide
          ? null
          : Drawer(
              backgroundColor: colors.sidebar,
              child: Builder(
                builder: (drawerContext) {
                  return SafeArea(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        splashColor: colors.textPrimary.withValues(alpha: 0.08),
                        highlightColor: Colors.transparent,
                        focusColor: colors.sidebarSelected,
                        hoverColor: AppColors.primary.withValues(alpha: 0.10),
                      ),
                      child: _AppSidebar(
                        expanded: true,
                        currentRoute: widget.currentRoute,
                        destinations: destinations,
                        pendingSubmittedCount: pendingCount,
                        onSelect: (route) {
                          Navigator.of(drawerContext).pop();
                          _goTo(route);
                        },
                        onLogout: _logout,
                        onProfile: () {
                          Navigator.of(drawerContext).pop();
                          _goTo(AppRoutes.profile);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
      body: Builder(
        builder: (scaffoldContext) {
          return Column(
            children: [
              _DashboardHeader(
                title: widget.title,
                onMenuPressed: () => _toggleNav(scaffoldContext),
                pendingCount: pendingCount,
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
                        color: colors.sidebar,
                        child: sidebar,
                      ),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.title,
    required this.onMenuPressed,
    this.pendingCount = 0,
    this.actions,
  });

  final String title;
  final VoidCallback onMenuPressed;
  final int pendingCount;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final company = context.watch<CompanyProvider>().selectedCompany;
    final colors = AppColors.of(context);

    return Material(
      color: colors.header,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
                children: [
                  IconButton(
                    tooltip: pendingCount > 0
                        ? 'Menu · ${PendingCountBadge.labelFor(pendingCount)} pending'
                        : 'Menu',
                    onPressed: onMenuPressed,
                    icon: BadgedIcon(
                      icon: Icons.menu_rounded,
                      count: pendingCount,
                      iconSize: 24,
                      color: colors.textPrimary,
                    ),
                    color: colors.textPrimary,
                    style: IconButton.styleFrom(
                      highlightColor: colors.textPrimary.withValues(
                        alpha: 0.08,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Image.asset('assets/branding/gmserp_logo.png'),
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (company != null)
                          Text(
                            company.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.sidebarMuted,
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
                        color: colors.chip,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        user.role.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
    );
  }
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({
    required this.expanded,
    required this.currentRoute,
    required this.destinations,
    required this.pendingSubmittedCount,
    required this.onSelect,
    required this.onLogout,
    required this.onProfile,
  });

  final bool expanded;
  final String currentRoute;
  final List<SidebarDestination> destinations;
  final int pendingSubmittedCount;
  final ValueChanged<String> onSelect;
  final VoidCallback onLogout;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final selected = currentRoute == AppRoutes.profile;
    final colors = AppColors.of(context);

    return ColoredBox(
      color: colors.sidebar,
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
              color: selected ? colors.sidebarSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onProfile,
                borderRadius: BorderRadius.circular(14),
                overlayColor: _sidebarOverlayColor(colors),
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
                                  Text(
                                    'GMSERP',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    user?.username.isNotEmpty == true
                                        ? user!.username
                                        : 'Account',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  if (user?.email.isNotEmpty == true)
                                    Text(
                                      user!.email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: colors.sidebarMuted,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: colors.border, height: 24),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final item in destinations)
                  if (item.children.isNotEmpty)
                    _NavDropdown(
                      destination: item,
                      expanded: expanded,
                      currentRoute: currentRoute,
                      onSelect: onSelect,
                    )
                  else if (item.route != null)
                    _NavTile(
                      expanded: expanded,
                      selected: item.route == currentRoute,
                      icon: item.icon,
                      label: item.label,
                      badgeCount: item.route == AppRoutes.superAdminRequests
                          ? pendingSubmittedCount
                          : 0,
                      onTap: () => onSelect(item.route!),
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: colors.border, height: 16),
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
    this.badgeCount = 0,
    this.foreground,
  });

  final bool expanded;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = foreground ?? colors.textPrimary;
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? colors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          overlayColor: _sidebarOverlayColor(colors),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 0,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment:
                  expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                BadgedIcon(
                  icon: icon,
                  count: expanded ? 0 : badgeCount,
                  iconSize: 22,
                  color: color,
                ),
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
                  if (badgeCount > 0) ...[
                    const SizedBox(width: 8),
                    PendingCountBadge(count: badgeCount),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (expanded) return tile;
    return Tooltip(
      message: badgeCount > 0
          ? '$label · ${PendingCountBadge.labelFor(badgeCount)} pending'
          : label,
      child: tile,
    );
  }
}

class _NavDropdown extends StatefulWidget {
  const _NavDropdown({
    required this.destination,
    required this.expanded,
    required this.currentRoute,
    required this.onSelect,
  });

  final SidebarDestination destination;
  final bool expanded;
  final String currentRoute;
  final ValueChanged<String> onSelect;

  @override
  State<_NavDropdown> createState() => _NavDropdownState();
}

class _NavDropdownState extends State<_NavDropdown> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.destination.containsRoute(widget.currentRoute);
  }

  @override
  void didUpdateWidget(covariant _NavDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.destination.containsRoute(widget.currentRoute)) {
      _open = true;
    }
  }

  Future<void> _showCollapsedMenu() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx + box.size.width,
        origin.dy,
        origin.dx + box.size.width + 200,
        origin.dy + box.size.height,
      ),
      items: [
        for (final child in widget.destination.children)
          if (child.route != null)
          PopupMenuItem<String>(
            value: child.route,
            child: Row(
              children: [
                Icon(child.icon, size: 20),
                const SizedBox(width: 10),
                Text(child.label),
              ],
            ),
          ),
      ],
    );
    if (selected != null) widget.onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final active = widget.destination.containsRoute(widget.currentRoute);

    if (!widget.expanded) {
      return Tooltip(
        message: widget.destination.label,
        child: _NavTile(
          expanded: false,
          selected: active,
          icon: widget.destination.icon,
          label: widget.destination.label,
          onTap: _showCollapsedMenu,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          Material(
            color: active && !_open
                ? colors.sidebarSelected
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(14),
              overlayColor: _sidebarOverlayColor(colors),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      widget.destination.icon,
                      color: colors.textPrimary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.destination.label,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight:
                              active ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 4),
              child: Column(
                children: [
                  for (final child in widget.destination.children)
                    if (child.route != null)
                      _NavTile(
                        expanded: true,
                        selected: child.route == widget.currentRoute,
                        icon: child.icon,
                        label: child.label,
                        onTap: () => widget.onSelect(child.route!),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

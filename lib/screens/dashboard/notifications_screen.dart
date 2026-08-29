import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/navigation/notification_sync.dart';
import '../../core/utils/active_page_load.dart';
import '../../core/utils/rtdb_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../models/activity_log_entry.dart';
import '../../models/time_entry.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/user_outcome_notifications_provider.dart';
import '../../services/activity_log_repository.dart';
import '../../services/rtdb/rtdb_desktop_limiter.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/lazy_list_pager.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with ActivePageLoad {
  final _repo = ActivityLogRepository();
  final _searchController = TextEditingController();
  late final LazyListPager _pager;

  List<ActivityLogEntry> _items = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _companyFilter = 'All';
  String _typeFilter = 'All';
  String _outcomeFilter = 'All';
  String _search = '';

  static const _allCompanies = 'All';
  int _loadGeneration = 0;

  bool get _isSuperAdmin =>
      context.read<AuthProvider>().user?.role == UserRole.superAdmin;

  /// Super Admin sees the full system audit trail; others see a personal inbox.
  bool get _auditMode => _isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _pager = LazyListPager(onChanged: _onPagerChanged);
  }

  @override
  void onPageActivated() {
    if (_isSuperAdmin) {
      context.read<CompanyProvider>().loadCompanies(force: false);
    }
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _loadGeneration++;
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _pager.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onPagerChanged() {
    if (!mounted) return;
    setState(() {});
    _markVisibleSeen();
  }

  Future<void> _markVisibleSeen() async {
    final visible = _pager.takeVisible(_filtered());
    if (visible.isEmpty || !mounted) return;
    // Clear header badge for Super Admin + personal inbox for other roles.
    await context.read<UserOutcomeNotificationsProvider>().markLoadedSeen(
          visible.map((e) => e.id),
        );
  }

  Future<void> _load({bool refresh = false}) async {
    final generation = ++_loadGeneration;
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      setState(() {
        _items = [];
        _loading = false;
        _error = 'Sign in to view activity.';
      });
      return;
    }

    final companies = context.read<CompanyProvider>();
    final needsCompany =
        user.role == UserRole.employee || user.role == UserRole.admin;
    if (needsCompany && !companies.notificationsAllowedFor(user.role)) {
      setState(() {
        _items = [];
        _loading = false;
        _error = 'Enter your company code to view notifications.';
      });
      return;
    }

    setState(() {
      if (refresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
      _pager.reset();
    });
    try {
      List<ActivityLogEntry>? items;
      List<ActivityLogEntry> personalEntries = const [];
      if (_auditMode) {
        if (preferRtdbPolling) {
          items = await RtdbDesktopLimiter.runHeavy(() async {
            final audit = await _repo.listResolved();
            if (generation != _loadGeneration || !mounted) return null;
            personalEntries = await _repo.listResolvedForUser(user.id);
            if (generation != _loadGeneration || !mounted) return null;
            final byId = <String, ActivityLogEntry>{};
            for (final entry in audit) {
              byId[entry.id] = entry;
            }
            for (final entry in personalEntries) {
              byId[entry.id] = entry;
            }
            return byId.values.toList()
              ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
          });
        } else {
          final results = await Future.wait([
            _repo.listResolved(),
            _repo.listResolvedForUser(user.id),
          ]);
          final audit = results[0];
          personalEntries = results[1];
          final byId = <String, ActivityLogEntry>{};
          for (final entry in audit) {
            byId[entry.id] = entry;
          }
          for (final entry in personalEntries) {
            byId[entry.id] = entry;
          }
          items = byId.values.toList()
            ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        }
      } else {
        final company = companies.selectedCompany;
        personalEntries = await _repo.listResolvedForUser(
          user.id,
          companyId: needsCompany ? company?.id : null,
          companyDocumentId: needsCompany ? company?.firestoreId : null,
        );
        items = personalEntries;
      }
      if (items == null || !mounted || generation != _loadGeneration) return;
      setState(() {
        _items = items!;
        _loading = false;
        _refreshing = false;
      });
      syncUserNotificationProviders(context);
      await context
          .read<UserOutcomeNotificationsProvider>()
          .applyPersonalActivityEntries(personalEntries);
      if (!mounted || generation != _loadGeneration) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markVisibleSeen();
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _items = [];
        _loading = false;
        _refreshing = false;
        _error = _auditMode
            ? 'Unable to load activity logs.'
            : 'Unable to load notifications.';
      });
    }
  }

  void _resetPaging() {
    setState(() => _pager.reset());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _markVisibleSeen();
    });
  }

  List<String> _companyOptions(CompanyProvider companies) {
    final labels = <String>{};
    for (final company in companies.companies) {
      final name = company.name.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    for (final item in _items) {
      final name = item.companyName.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    final sorted = labels.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_allCompanies, ...sorted];
  }

  bool _matchesCompany(
    ActivityLogEntry item,
    CompanyProvider companies,
  ) {
    if (_companyFilter == _allCompanies) return true;
    final selected = _companyFilter.trim().toLowerCase();
    if (item.companyName.trim().toLowerCase() == selected) return true;
    for (final company in companies.companies) {
      if (company.name.trim().toLowerCase() != selected) continue;
      if (item.companyId == company.id ||
          item.companyDocumentId == company.firestoreId) {
        return true;
      }
    }
    return false;
  }

  List<ActivityLogEntry> _filtered([CompanyProvider? companies]) {
    final query = _search.trim().toLowerCase();
    final companyProvider = companies ?? context.read<CompanyProvider>();
    final outcomes = context.read<UserOutcomeNotificationsProvider>();
    final list = _items.where((item) {
      if (_auditMode && !_matchesCompany(item, companyProvider)) return false;

      if (_typeFilter == 'Time in / out' || _typeFilter == 'Time card') {
        if (item.kind != ActivityLogKind.timeEdit &&
            item.kind != ActivityLogKind.clock &&
            item.kind != ActivityLogKind.timeCardSettings) {
          return false;
        }
      } else if (_typeFilter == 'Leave' && item.kind != ActivityLogKind.leave) {
        return false;
      } else if (_typeFilter == 'Salary' &&
          item.kind != ActivityLogKind.salaryRate) {
        return false;
      } else if (_typeFilter == 'Announcement' &&
          item.kind != ActivityLogKind.announcement) {
        return false;
      }

      if (_auditMode) {
        if (_outcomeFilter != 'All' &&
            item.status.toLowerCase() != _outcomeFilter.toLowerCase()) {
          return false;
        }
      } else {
        if (_outcomeFilter == 'Approved' && !item.isApproved) return false;
        if (_outcomeFilter == 'Declined' && !item.isRejected) return false;
        if (_outcomeFilter == 'Updated' &&
            !item.isSalaryUpdate &&
            !item.isTimeCardSettingsUpdate) {
          return false;
        }
        if (_outcomeFilter == 'Sent' && !item.isAnnouncement) return false;
      }

      if (query.isNotEmpty && !item.searchText.contains(query)) return false;
      return true;
    }).toList();

    list.sort((a, b) {
      if (_auditMode) {
        final aUnseen = outcomes.isTrackedUnseen(a.id);
        final bUnseen = outcomes.isTrackedUnseen(b.id);
        if (aUnseen != bUnseen) return aUnseen ? -1 : 1;
      }
      return b.occurredAt.compareTo(a.occurredAt);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final user = context.watch<AuthProvider>().user;
    final companies = context.watch<CompanyProvider>();
    final auditMode = user?.role == UserRole.superAdmin;
    final companyOptions = _companyOptions(companies);
    final companyFilter = companyOptions.contains(_companyFilter)
        ? _companyFilter
        : _allCompanies;
    final filtered = _filtered(companies);
    final visible = _pager.takeVisible(filtered);
    final hasMore = _pager.hasMore(filtered.length);
    final approvedCount = filtered.where((i) => i.isApproved).length;
    final declinedCount = filtered.where((i) => i.isRejected).length;

    final title = auditMode ? 'Activity' : 'Notifications';
    final outcomes = context.watch<UserOutcomeNotificationsProvider>();
    final unseen = outcomes.unseenCount;
    final subtitle = auditMode
        ? 'System logs across every company, plus updates for you '
            '(salary, announcements, and your request outcomes).'
            '${unseen > 0 ? ' · $unseen new for you' : ''}'
        : 'Request outcomes, time card updates, and salary changes for you. '
            'Items are marked seen only after they appear on screen.';

    return DashboardScaffold(
      title: title,
      currentRoute: AppRoutes.notifications,
      child: CustomScrollView(
        controller: _pager.scrollController,
        slivers: [
          SliverPadding(
            padding: density.pagePadding.copyWith(bottom: 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                CompactPageHeader(
                  title: title,
                  subtitle: subtitle,
                  trailing: IconButton(
                    tooltip: 'Refresh',
                    onPressed:
                        _loading || _refreshing ? null : () => _load(refresh: true),
                    icon: _refreshing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryDark,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ),
                SizedBox(height: density.sectionGap),
                CompactSummaryStrip(
                  items: [
                    CompactSummaryItem(
                      label: 'Total',
                      value: '${_items.length}',
                    ),
                    CompactSummaryItem(
                      label: 'Showing',
                      value: '${visible.length}',
                    ),
                    if (auditMode && unseen > 0)
                      CompactSummaryItem(
                        label: 'New for you',
                        value: '$unseen',
                        color: AppColors.primaryDark,
                      ),
                    CompactSummaryItem(
                      label: 'Approved',
                      value: '$approvedCount',
                      color: AppColors.success,
                    ),
                    CompactSummaryItem(
                      label: auditMode ? 'Rejected' : 'Declined',
                      value: '$declinedCount',
                      color: AppColors.error,
                    ),
                  ],
                ),
                SizedBox(height: density.sectionGap),
                if (auditMode) ...[
                  CompactFilterDropdown(
                    value: companyFilter,
                    items: companyOptions,
                    hint: 'Company',
                    onChanged: (v) {
                      setState(() => _companyFilter = v);
                      _resetPaging();
                    },
                  ),
                  SizedBox(height: density.cardGap),
                ],
                Row(
                  children: [
                    Expanded(
                      child: CompactFilterDropdown(
                        value: _typeFilter,
                        items: auditMode
                            ? const [
                                'All',
                                'Time card',
                                'Leave',
                                'Salary',
                                'Announcement',
                              ]
                            : const [
                                'All',
                                'Time in / out',
                                'Leave',
                                'Salary',
                                'Announcement',
                              ],
                        hint: 'Type',
                        onChanged: (v) {
                          setState(() => _typeFilter = v);
                          _resetPaging();
                        },
                      ),
                    ),
                    SizedBox(width: density.cardGap),
                    Expanded(
                      child: CompactFilterDropdown(
                        value: _outcomeFilter,
                        items: auditMode
                            ? const [
                                'All',
                                'Approved',
                                'Rejected',
                                'Updated',
                                'Sent',
                              ]
                            : const [
                                'All',
                                'Approved',
                                'Declined',
                                'Updated',
                                'Sent',
                              ],
                        hint: 'Outcome',
                        onChanged: (v) {
                          setState(() => _outcomeFilter = v);
                          _resetPaging();
                        },
                      ),
                    ),
                    IconButton(
                      visualDensity: density.compact
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                      tooltip: 'Refresh',
                      onPressed: _loading ? null : _load,
                      icon: Icon(
                        Icons.refresh_rounded,
                        size: density.compact ? 20 : 24,
                      ),
                      color: AppColors.primaryDark,
                    ),
                  ],
                ),
                SizedBox(height: density.cardGap),
                CompactSearchField(
                  controller: _searchController,
                  onChanged: (v) {
                    setState(() => _search = v);
                    _resetPaging();
                  },
                  hintText: auditMode
                      ? 'Search employee, company, admin, date…'
                      : 'Search date, company, details…',
                ),
                SizedBox(height: density.sectionGap),
                if (_loading)
                  AppLoadingView(
                    title: auditMode
                        ? 'Loading activity'
                        : 'Loading notifications',
                    message: auditMode
                        ? 'Fetching system activity history…'
                        : 'Fetching approved and declined requests…',
                  )
                else if (_error != null)
                  _EmptyCard(icon: Icons.error_outline, message: _error!)
                else if (filtered.isEmpty)
                  _EmptyCard(
                    icon: auditMode
                        ? Icons.history_rounded
                        : Icons.notifications_none_rounded,
                    message: auditMode
                        ? 'No activity matches the current filters.'
                        : 'No approved or declined requests yet.',
                  ),
              ]),
            ),
          ),
          if (!_loading && _error == null && filtered.isNotEmpty)
            SliverPadding(
              padding: density.pagePadding.copyWith(top: 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= visible.length) {
                      return LazyListFooter(
                        hasMore: hasMore,
                        remaining: filtered.length - visible.length,
                        loadingMore: _pager.loadingMore,
                        onLoadMore: () => _pager.loadMore(filtered.length),
                      );
                    }
                    return _ActivityRow(
                      entry: visible[index],
                      auditStyle: auditMode,
                      isNew: outcomes.isTrackedUnseen(visible[index].id),
                    );
                  },
                  childCount: visible.length + (hasMore ? 1 : 0),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.entry,
    required this.auditStyle,
    this.isNew = false,
  });

  final ActivityLogEntry entry;
  final bool auditStyle;
  final bool isNew;

  String get _outcomeLabel => entry.isAnnouncement
      ? 'Sent'
      : entry.isSalaryUpdate || entry.isTimeCardSettingsUpdate
          ? 'Updated'
          : entry.isRejected
              ? (auditStyle ? 'Rejected' : 'Declined')
              : entry.statusLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final statusColor = entry.isAnnouncement ||
            entry.isSalaryUpdate ||
            entry.isTimeCardSettingsUpdate
        ? AppColors.primaryDark
        : entry.isApproved
            ? AppColors.success
            : entry.isRejected
                ? AppColors.error
                : colors.textSecondary;
    final kindColor = switch (entry.kind) {
      ActivityLogKind.timeEdit => AppColors.primaryDark,
      ActivityLogKind.clock => const Color(0xFF0F766E),
      ActivityLogKind.leave => const Color(0xFF2563EB),
      ActivityLogKind.salaryRate => const Color(0xFF7C3AED),
      ActivityLogKind.timeCardSettings => const Color(0xFF9333EA),
      ActivityLogKind.announcement => const Color(0xFFEA580C),
    };
    final kindLabel = auditStyle
        ? entry.kindLabel
        : switch (entry.kind) {
            ActivityLogKind.timeEdit => 'Time card',
            ActivityLogKind.clock => 'Time in / out',
            ActivityLogKind.leave => 'Leave',
            ActivityLogKind.salaryRate => 'Salary',
            ActivityLogKind.timeCardSettings => 'Time card',
            ActivityLogKind.announcement => 'Announcement',
          };

    return Container(
      margin: EdgeInsets.only(bottom: density.cardGap),
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(
          color: isNew ? AppColors.primaryDark : colors.border,
          width: isNew ? 1.5 : 1,
        ),
        boxShadow: isNew
            ? [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: density.cardGap,
            runSpacing: density.titleSubtitleGap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isNew)
                _MiniChip(label: 'New for you', color: AppColors.primaryDark),
              _MiniChip(label: kindLabel, color: kindColor),
              _MiniChip(label: _outcomeLabel, color: statusColor),
              Text(
                _formatWhen(entry.occurredAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: density.captionSize,
                    ),
              ),
            ],
          ),
          SizedBox(height: density.titleSubtitleGap),
          Text(
            entry.summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: density.cardTitleSize,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
          ),
          if (auditStyle) ...[
            SizedBox(height: density.compact ? 2 : 4),
            Text(
              '${entry.subjectName.isEmpty ? 'Employee' : entry.subjectName}'
              '${entry.companyName.isEmpty ? '' : ' · ${entry.companyName}'}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: density.bodySize,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ] else if (entry.companyName.isNotEmpty) ...[
            SizedBox(height: density.compact ? 2 : 4),
            Text(
              entry.companyName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: density.bodySize,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          if (entry.kind == ActivityLogKind.timeEdit) ...[
            if (entry.workDate.isNotEmpty)
              Text(
                'Date ${entry.workDate}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: density.captionSize,
                    ),
              ),
            if (entry.actorName.isNotEmpty)
              Text(
                'Requested by ${entry.actorName}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: density.captionSize,
                    ),
              ),
            if (!auditStyle && entry.subjectName.isNotEmpty)
              Text(
                'Employee ${entry.subjectName}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: density.captionSize,
                    ),
              ),
          ],
          if (entry.kind == ActivityLogKind.clock && entry.workDate.isNotEmpty)
            Text(
              'Date ${entry.workDate}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: density.captionSize,
                  ),
            ),
          if (entry.decisionLabel.isNotEmpty)
            Text(
              entry.decisionLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: density.captionSize,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          if (entry.kind == ActivityLogKind.leave &&
              entry.leaveRange.isNotEmpty)
            Text(
              entry.leaveRange,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: density.captionSize,
                  ),
            ),
          if (entry.kind == ActivityLogKind.salaryRate ||
              entry.kind == ActivityLogKind.timeCardSettings) ...[
            if (!auditStyle && entry.subjectName.isNotEmpty)
              Text(
                'Employee ${entry.subjectName}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: density.captionSize,
                    ),
              ),
            if (entry.actorName.isNotEmpty)
              Text(
                'Updated by ${entry.actorName}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: density.captionSize,
                    ),
              ),
          ],
          if (entry.kind == ActivityLogKind.announcement &&
              entry.actorName.isNotEmpty)
            Text(
              'From ${entry.actorName}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: density.captionSize,
                  ),
            ),
          SizedBox(height: density.titleSubtitleGap),
          Text(
            entry.detail,
            softWrap: true,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600,
                  fontSize: density.bodySize,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: density.compact ? 7 : 9,
        vertical: density.compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: density.chipLabelSize,
            ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: density.compact ? 22 : 26,
        horizontal: density.compact ? 12 : 16,
      ),
      decoration: compactCardDecoration(context),
      child: Column(
        children: [
          Icon(icon, size: density.compact ? 26 : 30, color: colors.textSecondary),
          SizedBox(height: density.cardGap + 2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: density.bodySize,
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

String _formatWhen(DateTime when) {
  final local = when.toLocal();
  return '${formatWorkDate(local)} · ${formatClockTime(local)}';
}

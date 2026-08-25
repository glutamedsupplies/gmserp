import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/activity_log_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_outcome_notifications_provider.dart';
import '../../services/activity_log_repository.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _pageSize = 20;

  final _repo = ActivityLogRepository();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<ActivityLogEntry> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _typeFilter = 'All';
  String _outcomeFilter = 'All';
  String _search = '';
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 240) return;
    _loadMore();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      setState(() {
        _items = [];
        _loading = false;
        _error = 'Sign in to view notifications.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _visibleCount = _pageSize;
    });
    try {
      final items = await _repo.listResolvedForUser(user.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _visibleCount = _pageSize.clamp(0, items.length);
      });
      // Opening this page + loading results marks them seen.
      await context.read<UserOutcomeNotificationsProvider>().markLoadedSeen(
            items.map((e) => e.id),
          );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
        _error = 'Unable to load notifications.';
      });
    }
  }

  void _loadMore() {
    final filtered = _filtered;
    if (_visibleCount >= filtered.length) return;
    setState(() {
      _loadingMore = true;
      _visibleCount =
          (_visibleCount + _pageSize).clamp(0, filtered.length);
    });
    // Yield so the loading indicator can paint, then clear flag.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    });
  }

  void _resetPaging() {
    setState(() {
      _visibleCount = _pageSize;
      _loadingMore = false;
    });
  }

  List<ActivityLogEntry> get _filtered {
    final query = _search.trim().toLowerCase();
    return _items.where((item) {
      if (_typeFilter == 'Time in / out' &&
          item.kind != ActivityLogKind.timeEdit) {
        return false;
      }
      if (_typeFilter == 'Leave' && item.kind != ActivityLogKind.leave) {
        return false;
      }
      if (_outcomeFilter == 'Approved' && !item.isApproved) return false;
      if (_outcomeFilter == 'Declined' && !item.isRejected) return false;
      if (query.isNotEmpty && !item.searchText.contains(query)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final filtered = _filtered;
    final visible = filtered.take(_visibleCount).toList();
    final hasMore = _visibleCount < filtered.length;
    final approvedCount = filtered.where((i) => i.isApproved).length;
    final declinedCount = filtered.where((i) => i.isRejected).length;

    return DashboardScaffold(
      title: 'Notifications',
      currentRoute: AppRoutes.notifications,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: density.pagePadding.copyWith(bottom: 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const CompactPageHeader(
                  title: 'Notifications',
                  subtitle:
                      'Approved and declined time in / out and leave requests. '
                      'Opening this page marks them as seen.',
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
                    CompactSummaryItem(
                      label: 'Approved',
                      value: '$approvedCount',
                      color: AppColors.success,
                    ),
                    CompactSummaryItem(
                      label: 'Declined',
                      value: '$declinedCount',
                      color: AppColors.error,
                    ),
                  ],
                ),
                SizedBox(height: density.sectionGap),
                Row(
                  children: [
                    Expanded(
                      child: CompactFilterDropdown(
                        value: _typeFilter,
                        items: const ['All', 'Time in / out', 'Leave'],
                        hint: 'Type',
                        onChanged: (v) {
                          setState(() => _typeFilter = v);
                          _resetPaging();
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: CompactFilterDropdown(
                        value: _outcomeFilter,
                        items: const ['All', 'Approved', 'Declined'],
                        hint: 'Outcome',
                        onChanged: (v) {
                          setState(() => _outcomeFilter = v);
                          _resetPaging();
                        },
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Refresh',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      color: AppColors.primaryDark,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                CompactSearchField(
                  controller: _searchController,
                  onChanged: (v) {
                    setState(() => _search = v);
                    _resetPaging();
                  },
                  hintText: 'Search date, company, details…',
                ),
                SizedBox(height: density.sectionGap),
                if (_loading)
                  const AppLoadingView(
                    title: 'Loading notifications',
                    message: 'Fetching approved and declined requests…',
                  )
                else if (_error != null)
                  _EmptyCard(icon: Icons.error_outline, message: _error!)
                else if (filtered.isEmpty)
                  const _EmptyCard(
                    icon: Icons.notifications_none_rounded,
                    message: 'No approved or declined requests yet.',
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
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: _loadingMore
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : TextButton(
                                  onPressed: _loadMore,
                                  child: Text(
                                    'Load more (${filtered.length - visible.length} left)',
                                  ),
                                ),
                        ),
                      );
                    }
                    return _NotificationRow(entry: visible[index]);
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

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.entry});

  final ActivityLogEntry entry;

  String get _outcomeLabel => entry.isRejected ? 'Declined' : entry.statusLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final statusColor = entry.isApproved
        ? AppColors.success
        : entry.isRejected
            ? AppColors.error
            : colors.textSecondary;
    final kindColor = entry.kind == ActivityLogKind.timeEdit
        ? AppColors.primaryDark
        : const Color(0xFF2563EB);
    final kindLabel =
        entry.kind == ActivityLogKind.timeEdit ? 'Time in / out' : 'Leave';

    return Container(
      margin: EdgeInsets.only(bottom: CompactPageStyle.of(context).cardGap),
      padding: CompactPageStyle.of(context).cardPadding,
      decoration: compactCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MiniChip(label: kindLabel, color: kindColor),
              _MiniChip(label: _outcomeLabel, color: statusColor),
              Text(
                _formatWhen(entry.occurredAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 10,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
          ),
          if (entry.companyName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              entry.companyName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                      fontSize: 10,
                    ),
              ),
            if (entry.actorName.isNotEmpty)
              Text(
                'Requested by ${entry.actorName}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 10,
                    ),
              ),
            if (entry.subjectName.isNotEmpty)
              Text(
                'Employee ${entry.subjectName}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 10,
                    ),
              ),
          ],
          if (entry.kind == ActivityLogKind.leave &&
              entry.leaveRange.isNotEmpty)
            Text(
              entry.leaveRange,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: 10,
                  ),
            ),
          const SizedBox(height: 3),
          Text(
            entry.detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
          ),
        ],
      ),
    );
  }

  String _formatWhen(DateTime value) {
    final local = value.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      decoration: compactCardDecoration(context),
      child: Column(
        children: [
          Icon(icon, size: 28, color: colors.textSecondary),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

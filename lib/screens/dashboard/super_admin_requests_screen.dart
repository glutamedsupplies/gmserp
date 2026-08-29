import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/active_page_load.dart';
import '../../core/utils/rtdb_platform.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/clock_request.dart';
import '../../models/company_model.dart';
import '../../models/leave_request.dart';
import '../../models/staff_assignment.dart';
import '../../models/time_card_change_request.dart';
import '../../models/time_entry.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../services/clock_request_repository.dart';
import '../../services/leave_request_repository.dart';
import '../../services/time_card_change_request_repository.dart';
import '../../services/rtdb/rtdb_desktop_limiter.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/lazy_list_pager.dart';

class SuperAdminRequestsScreen extends StatefulWidget {
  const SuperAdminRequestsScreen({
    super.key,
    this.focusRequestType,
    this.focusRequestId,
  });

  /// `leave` or `time` from a notification payload.
  final String? focusRequestType;
  final String? focusRequestId;

  @override
  State<SuperAdminRequestsScreen> createState() =>
      _SuperAdminRequestsScreenState();
}

class _SuperAdminRequestsScreenState extends State<SuperAdminRequestsScreen>
    with ActivePageLoad {
  final _leaveRepo = LeaveRequestRepository();
  final _timeChangeRepo = TimeCardChangeRequestRepository();
  final _clockRepo = ClockRequestRepository();
  final _searchController = TextEditingController();
  final _focusKey = GlobalKey();
  late final LazyListPager _pager;

  List<LeaveRequest> _leaveRequests = [];
  List<TimeCardChangeRequest> _timeRequests = [];
  List<ClockRequest> _clockRequests = [];
  final Map<String, int> _clockDeclines = {};
  bool _loading = true;
  String? _error;
  String _companyFilter = 'All';
  String _typeFilter = 'All';
  String _statusFilter = 'All';
  String _search = '';
  String? _focusType;
  String? _focusId;
  bool _didApplyFocus = false;
  int _loadGeneration = 0;

  static const _allCompanies = 'All';

  @override
  void initState() {
    super.initState();
    _pager = LazyListPager(onChanged: () {
      if (mounted) setState(() {});
    });
    _focusType = widget.focusRequestType?.trim().toLowerCase();
    _focusId = widget.focusRequestId?.trim();
    if (_focusId != null && _focusId!.isNotEmpty) {
      _statusFilter = 'Pending';
      if (_focusType == 'leave') {
        _typeFilter = 'Leave';
      } else if (_focusType == 'time') {
        _typeFilter = 'Time edit';
      } else if (_focusType == 'clock') {
        _typeFilter = 'Time in/out';
      }
    }
  }

  @override
  void onPageActivated() {
    context.read<CompanyProvider>().loadCompanies(force: false);
    if (preferRtdbPolling) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && TickerMode.valuesOf(context).enabled) _load();
      });
    } else {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _loadGeneration++;
    }
  }

  @override
  void didUpdateWidget(covariant SuperAdminRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusRequestId != widget.focusRequestId ||
        oldWidget.focusRequestType != widget.focusRequestType) {
      _focusType = widget.focusRequestType?.trim().toLowerCase();
      _focusId = widget.focusRequestId?.trim();
      _didApplyFocus = false;
      if (_focusId != null && _focusId!.isNotEmpty) {
        setState(() {
          _statusFilter = 'Pending';
          if (_focusType == 'leave') {
            _typeFilter = 'Leave';
          } else if (_focusType == 'time') {
            _typeFilter = 'Time edit';
          } else if (_focusType == 'clock') {
            _typeFilter = 'Time in/out';
          }
          _pager.reset();
        });
        _scrollToFocus();
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _pager.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _declineKey(String companyId, String userId) => '$companyId|$userId';

  bool _isClockLocked(ClockRequest request) {
    final count = _clockDeclines[_declineKey(request.companyId, request.userId)];
    return (count ?? 0) >= StaffAssignment.clockDeclineLimit;
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _pager.reset();
    });
    try {
      await RtdbDesktopLimiter.runHeavy(() async {
        late List<LeaveRequest> leaves;
        late List<TimeCardChangeRequest> times;
        late List<ClockRequest> clocks;
        if (preferRtdbPolling) {
          leaves = await _leaveRepo.listAll();
          if (generation != _loadGeneration || !mounted) return;
          times = await _timeChangeRepo.listAll(hydrate: false);
          if (generation != _loadGeneration || !mounted) return;
          clocks = await _clockRepo.listAll();
        } else {
          final results = await Future.wait([
            _leaveRepo.listAll(),
            _timeChangeRepo.listAll(),
            _clockRepo.listAll(),
          ]);
          leaves = results[0] as List<LeaveRequest>;
          times = results[1] as List<TimeCardChangeRequest>;
          clocks = results[2] as List<ClockRequest>;
        }
        if (generation != _loadGeneration || !mounted) return;

        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _leaveRequests = leaves;
          _timeRequests = times;
          _clockRequests = clocks;
          _loading = false;
        });
        _scrollToFocus();

        final pairs = <({String companyId, String userId})>{};
        for (final clock in clocks) {
          pairs.add((companyId: clock.companyId, userId: clock.userId));
        }
        if (pairs.isEmpty || generation != _loadGeneration || !mounted) {
          return;
        }
        final companyProvider = context.read<CompanyProvider>();
        final declines =
            await companyProvider.clockDeclineCountsFor(members: pairs);
        if (generation != _loadGeneration || !mounted) return;
        setState(() {
          _clockDeclines
            ..clear()
            ..addAll(declines);
        });
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _leaveRequests = [];
        _timeRequests = [];
        _clockRequests = [];
        _clockDeclines.clear();
        _loading = false;
        _error = 'Unable to load requests.';
      });
    }
  }

  bool _isFocused(_UnifiedRequest item) {
    final id = _focusId;
    if (id == null || id.isEmpty) return false;
    if (item.leave != null) {
      return (_focusType == null ||
              _focusType!.isEmpty ||
              _focusType == 'leave') &&
          item.leave!.id == id;
    }
    if (item.timeEdit != null) {
      return (_focusType == null ||
              _focusType!.isEmpty ||
              _focusType == 'time') &&
          item.timeEdit!.id == id;
    }
    if (item.clock != null) {
      return (_focusType == null ||
              _focusType!.isEmpty ||
              _focusType == 'clock') &&
          item.clock!.id == id;
    }
    return false;
  }

  void _scrollToFocus() {
    if (_didApplyFocus) return;
    if (_focusId == null || _focusId!.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _focusKey.currentContext;
      if (ctx == null || !mounted) return;
      _didApplyFocus = true;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
    });
  }

  List<String> _companyOptions(CompanyProvider companies) {
    final labels = <String>{};
    for (final company in companies.companies) {
      final name = company.name.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    for (final leave in _leaveRequests) {
      final name = leave.companyName.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    for (final change in _timeRequests) {
      final name = change.companyName.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    for (final clock in _clockRequests) {
      final name = clock.companyName.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    final sorted = labels.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_allCompanies, ...sorted];
  }

  bool _matchesCompany(
    _UnifiedRequest item,
    CompanyProvider companies, {
    required String companyFilter,
    CompanyModel? lockedCompany,
  }) {
    if (lockedCompany != null) {
      return _matchesLockedCompany(item, lockedCompany);
    }
    if (companyFilter == _allCompanies) return true;

    final selected = companyFilter.trim().toLowerCase();
    if (item.companyName.trim().toLowerCase() == selected) return true;

    for (final company in companies.companies) {
      if (company.name.trim().toLowerCase() != selected) continue;
      if (_matchesLockedCompany(item, company)) return true;
    }
    return false;
  }

  bool _matchesLockedCompany(_UnifiedRequest item, CompanyModel company) {
    if (item.companyId == company.id ||
        item.companyDocumentId == company.firestoreId ||
        item.companyId == company.firestoreId ||
        item.companyDocumentId == company.id) {
      return true;
    }
    return item.companyName.trim().toLowerCase() ==
        company.name.trim().toLowerCase();
  }

  List<_UnifiedRequest> _filtered(
    CompanyProvider companies, {
    required String companyFilter,
    CompanyModel? lockedCompany,
  }) {
    final query = _search.trim().toLowerCase();
    final items = <_UnifiedRequest>[
      if (_typeFilter == 'All' || _typeFilter == 'Leave')
        for (final leave in _leaveRequests) _UnifiedRequest.leave(leave),
      if (_typeFilter == 'All' || _typeFilter == 'Time edit')
        for (final change in _timeRequests) _UnifiedRequest.timeEdit(change),
      if (_typeFilter == 'All' || _typeFilter == 'Time in/out')
        for (final clock in _clockRequests) _UnifiedRequest.clock(clock),
    ];

    items.sort((a, b) {
      final byCreated = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (byCreated != 0) return byCreated;
      return b.sortKey.compareTo(a.sortKey);
    });

    return items.where((item) {
      if (!_matchesCompany(
        item,
        companies,
        companyFilter: companyFilter,
        lockedCompany: lockedCompany,
      )) {
        return false;
      }
      if (_statusFilter != 'All') {
        final wanted = _statusFilter.toLowerCase();
        final actual = item.status.toLowerCase();
        if (wanted == 'pending') {
          final reviewable = item.clock?.awaitsReview == true ||
              (item.clock == null &&
                  (item.leave?.status.toLowerCase() == 'pending' ||
                      item.timeEdit?.isPending == true));
          if (!reviewable) return false;
        } else if (actual != wanted) {
          return false;
        }
      }
      if (query.isEmpty) return true;
      return item.searchText.contains(query);
    }).toList();
  }

  Future<void> _updateLeaveStatus(LeaveRequest request, String status) async {
    final reviewer = _reviewer();
    try {
      await _leaveRepo.updateStatus(
        requestId: request.id,
        status: status,
        reviewerId: reviewer.$1,
        reviewerName: reviewer.$2,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        status == 'approved'
            ? 'Leave request approved.'
            : 'Leave request rejected.',
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Could not update leave request.');
    }
  }

  Future<void> _approveTimeChange(TimeCardChangeRequest request) async {
    final reviewer = _reviewer();
    try {
      await _timeChangeRepo.approve(
        request,
        reviewerId: reviewer.$1,
        reviewerName: reviewer.$2,
      );
      if (!mounted) return;
      // Approving a time-card edit unlocks clock requests after 3 declines.
      await context.read<CompanyProvider>().unlockEmployeeClockRequests(
            companyId: request.companyDocumentId.isNotEmpty
                ? request.companyDocumentId
                : request.companyId,
            userId: request.employeeId,
          );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        'Time change approved and saved to the time card.',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        e is StateError ? e.message : 'Could not approve time change.',
      );
    }
  }

  Future<void> _rejectTimeChange(TimeCardChangeRequest request) async {
    final reviewer = _reviewer();
    try {
      await _timeChangeRepo.reject(
        request.id,
        reviewerId: reviewer.$1,
        reviewerName: reviewer.$2,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        'Time change request rejected. No database changes were made.',
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Could not reject time change.');
    }
  }

  Future<void> _approveClock(ClockRequest request) async {
    final reviewer = _reviewer();
    try {
      await _clockRepo.approve(
        request,
        reviewerId: reviewer.$1,
        reviewerName: reviewer.$2,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        request.isClockIn
            ? 'Time in approved and saved.'
                '${_hasPendingClockOutFor(request) ? ' Approve time out next for that day.' : ''}'
            : 'Time out approved and saved.',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        e is StateError ? e.message : 'Could not approve clock request.',
      );
    }
  }

  Future<void> _rejectClock(ClockRequest request) async {
    final reviewer = _reviewer();
    final alsoDeclineOut =
        request.isClockIn && _hasPendingClockOutFor(request);
    try {
      await _clockRepo.reject(
        request,
        reviewerId: reviewer.$1,
        reviewerName: reviewer.$2,
      );
      if (!mounted) return;
      final companyProvider = context.read<CompanyProvider>();
      final declines = await companyProvider.clockDeclineCountFor(
            companyId: request.companyId,
            userId: request.userId,
          );
      if (!mounted) return;
      final locked = declines >= StaffAssignment.clockDeclineLimit;
      setState(() {
        _clockDeclines[_declineKey(request.companyId, request.userId)] =
            declines;
      });
      final base = request.isClockIn
          ? (alsoDeclineOut
              ? 'Time in declined. Matching time out for that day was also declined.'
              : 'Time in declined. No time card changes were made.')
          : 'Time out declined. No time card changes were made.';
      final suffix = locked
          ? ' Employee is now locked after $declines declines — unlock or edit their time card settings.'
          : declines > 0
              ? ' Declines: $declines/${StaffAssignment.clockDeclineLimit}.'
              : '';
      SnackBarHelper.showSuccess(context, '$base$suffix');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        e is StateError ? e.message : 'Could not reject clock request.',
      );
    }
  }

  Future<void> _unlockClockRequests(ClockRequest request) async {
    final ok = await context.read<CompanyProvider>().unlockEmployeeClockRequests(
          companyId: request.companyId,
          userId: request.userId,
        );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(
        context,
        'Clock requests unlocked for this employee.',
      );
      await _load();
    } else {
      SnackBarHelper.showError(
        context,
        context.read<CompanyProvider>().errorMessage ??
            'Could not unlock clock requests.',
      );
    }
  }

  bool _hasPendingClockOutFor(ClockRequest clockIn) {
    if (!clockIn.isClockIn) return false;
    return _clockRequests.any(
      (item) =>
          item.isPending &&
          item.isClockOut &&
          item.userId == clockIn.userId &&
          item.companyId == clockIn.companyId &&
          item.workDate == clockIn.workDate,
    );
  }

  bool _hasPendingClockInForOut(ClockRequest clockOut) {
    if (!clockOut.isClockOut) return false;
    return _clockRequests.any(
      (item) =>
          item.awaitsReview &&
          item.isClockIn &&
          item.userId == clockOut.userId &&
          item.companyId == clockOut.companyId &&
          item.workDate == clockOut.workDate,
    );
  }

  (String, String) _reviewer() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return ('', 'Unknown');
    final name = user.username.trim().isNotEmpty ? user.username.trim() : user.email;
    return (user.id, name.isEmpty ? 'Admin' : name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final companies = context.watch<CompanyProvider>();
    final authUser = context.watch<AuthProvider>().user;
    final isAdminOnly = authUser?.role == UserRole.admin;
    final lockedCompany = isAdminOnly ? companies.selectedCompany : null;

    final companyOptions = _companyOptions(companies);
    final companyFilter = lockedCompany != null
        ? lockedCompany.name
        : (companyOptions.contains(_companyFilter)
            ? _companyFilter
            : _allCompanies);
    if (!isAdminOnly && companyFilter != _companyFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _companyFilter = companyFilter);
      });
    }
    final filtered = _filtered(
      companies,
      companyFilter: companyFilter,
      lockedCompany: lockedCompany,
    );
    final visible = _pager.takeVisible(filtered);
    final hasMore = _pager.hasMore(filtered.length);

    bool inScope(_UnifiedRequest item) => _matchesCompany(
          item,
          companies,
          companyFilter: companyFilter,
          lockedCompany: lockedCompany,
        );

    final scopedLeaves = lockedCompany == null
        ? _leaveRequests
        : _leaveRequests
            .where((r) => inScope(_UnifiedRequest.leave(r)))
            .toList();
    final scopedTime = lockedCompany == null
        ? _timeRequests
        : _timeRequests
            .where((r) => inScope(_UnifiedRequest.timeEdit(r)))
            .toList();
    final scopedClock = lockedCompany == null
        ? _clockRequests
        : _clockRequests
            .where((r) => inScope(_UnifiedRequest.clock(r)))
            .toList();

    final pendingCount = filtered
        .where((item) => item.status.toLowerCase() == 'pending')
        .length;
    final totalPending = [
      ...scopedLeaves.where((r) => r.status.toLowerCase() == 'pending'),
      ...scopedTime.where((r) => r.isPending),
      ...scopedClock.where((r) => r.awaitsReview),
    ].length;

    return DashboardScaffold(
      title: 'Requests',
      currentRoute: AppRoutes.superAdminRequests,
      child: ListView(
        controller: _pager.scrollController,
        padding: density.pagePadding,
        children: [
          CompactPageHeader(
            title: 'Requests',
            subtitle: isAdminOnly
                ? (lockedCompany == null
                    ? 'Select a company to review requests for your workplace.'
                    : 'Review leave, time in/out, and time-card change requests for ${lockedCompany.name}.')
                : 'Review leave, employee time in/out, and admin time-card change requests.',
          ),
          SizedBox(height: density.sectionGap),
          if (isAdminOnly && lockedCompany == null)
            const _MessageCard(
              icon: Icons.business_outlined,
              message: 'Select a company to view requests.',
            )
          else ...[
            CompactSummaryStrip(
              items: [
                CompactSummaryItem(
                  label: 'Total',
                  value:
                      '${scopedLeaves.length + scopedTime.length + scopedClock.length}',
                ),
                CompactSummaryItem(label: 'Pending', value: '$totalPending'),
                CompactSummaryItem(
                  label: 'Showing',
                  value: '${visible.length}',
                ),
              ],
            ),
            SizedBox(height: density.sectionGap),
            if (!isAdminOnly) ...[
              CompactFilterDropdown(
                value: companyFilter,
                items: companyOptions,
                hint: 'Company',
                onChanged: (value) => setState(() {
                  _companyFilter = value;
                  _pager.reset();
                }),
              ),
              SizedBox(height: density.cardGap),
            ],
            Row(
              children: [
                Expanded(
                  child: CompactFilterDropdown(
                    value: _typeFilter,
                    items: const ['All', 'Leave', 'Time in/out', 'Time edit'],
                    hint: 'Type',
                    onChanged: (value) => setState(() {
                      _typeFilter = value;
                      _pager.reset();
                    }),
                  ),
                ),
                SizedBox(width: density.cardGap),
                Expanded(
                  child: CompactFilterDropdown(
                    value: _statusFilter,
                    items: const ['All', 'Pending', 'Approved', 'Rejected'],
                    hint: 'Status',
                    onChanged: (value) => setState(() {
                      _statusFilter = value;
                      _pager.reset();
                    }),
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
              onChanged: (value) => setState(() {
                _search = value;
                _pager.reset();
              }),
              hintText: isAdminOnly
                  ? 'Search employee, admin, or reason'
                  : 'Search employee, company, admin, or reason',
            ),
            if (!isAdminOnly && companyFilter != _allCompanies) ...[
              SizedBox(height: density.cardGap),
              Text(
                'Showing requests for $companyFilter'
                '${pendingCount > 0 ? ' · $pendingCount pending' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            if (isAdminOnly && lockedCompany != null) ...[
              SizedBox(height: density.cardGap),
              Text(
                'Company: ${lockedCompany.name}'
                '${pendingCount > 0 ? ' · $pendingCount pending' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            SizedBox(height: density.sectionGap),
            if (_loading)
              const AppLoadingView(
                title: 'Loading requests',
                message: 'Fetching pending requests…',
              )
            else if (_error != null)
              _MessageCard(icon: Icons.error_outline, message: _error!)
            else if (filtered.isEmpty)
              const _MessageCard(
                icon: Icons.inbox_outlined,
                message: 'No requests match the current filters.',
              )
            else ...[
              for (final item in visible)
                if (item.leave != null)
                  KeyedSubtree(
                    key: _isFocused(item)
                        ? _focusKey
                        : ValueKey('leave-${item.leave!.id}'),
                    child: _LeaveRequestCard(
                      request: item.leave!,
                      highlighted: _isFocused(item),
                      onApprove: item.leave!.status.toLowerCase() == 'pending'
                          ? () => _updateLeaveStatus(item.leave!, 'approved')
                          : null,
                      onReject: item.leave!.status.toLowerCase() == 'pending'
                          ? () => _updateLeaveStatus(item.leave!, 'rejected')
                          : null,
                    ),
                  )
                else if (item.timeEdit != null)
                  KeyedSubtree(
                    key: _isFocused(item)
                        ? _focusKey
                        : ValueKey('time-${item.timeEdit!.id}'),
                    child: _TimeEditRequestCard(
                      request: item.timeEdit!,
                      highlighted: _isFocused(item),
                      onApprove: item.timeEdit!.isPending
                          ? () => _approveTimeChange(item.timeEdit!)
                          : null,
                      onReject: item.timeEdit!.isPending
                          ? () => _rejectTimeChange(item.timeEdit!)
                          : null,
                    ),
                  )
                else if (item.clock != null)
                  KeyedSubtree(
                    key: _isFocused(item)
                        ? _focusKey
                        : ValueKey('clock-${item.clock!.id}'),
                    child: Builder(
                      builder: (context) {
                        final clock = item.clock!;
                        final locked = _isClockLocked(clock);
                        return _ClockRequestCard(
                          request: clock,
                          highlighted: _isFocused(item),
                          awaitingTimeInApproval: clock.isClockOut &&
                              clock.awaitsReview &&
                              _hasPendingClockInForOut(clock),
                          showUnlock: locked,
                          onUnlock: locked
                              ? () => _unlockClockRequests(clock)
                              : null,
                          onApprove: clock.awaitsReview &&
                                  !(clock.isClockOut &&
                                      _hasPendingClockInForOut(clock))
                              ? () => _approveClock(clock)
                              : null,
                          onReject: clock.awaitsReview
                              ? () => _rejectClock(clock)
                              : null,
                        );
                      },
                    ),
                  ),
              LazyListFooter(
                hasMore: hasMore,
                remaining: filtered.length - visible.length,
                loadingMore: _pager.loadingMore,
                onLoadMore: () => _pager.loadMore(filtered.length),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _UnifiedRequest {
  const _UnifiedRequest._({
    required this.status,
    required this.createdAt,
    required this.sortKey,
    required this.searchText,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    this.leave,
    this.timeEdit,
    this.clock,
  });

  factory _UnifiedRequest.leave(LeaveRequest leave) {
    return _UnifiedRequest._(
      leave: leave,
      status: leave.status,
      createdAt: leave.createdAt,
      sortKey: leave.startDate,
      companyId: leave.companyId,
      companyDocumentId: leave.companyDocumentId,
      companyName: leave.companyName,
      searchText: [
        leave.username,
        leave.userEmail,
        leave.companyName,
        leave.reason,
        'leave',
      ].join(' ').toLowerCase(),
    );
  }

  factory _UnifiedRequest.timeEdit(TimeCardChangeRequest change) {
    return _UnifiedRequest._(
      timeEdit: change,
      status: change.status,
      createdAt: change.createdAt,
      sortKey: change.workDate,
      companyId: change.companyId,
      companyDocumentId: change.companyDocumentId,
      companyName: change.companyName,
      searchText: [
        change.employeeName,
        change.employeeEmail,
        change.companyName,
        change.requesterName,
        change.requesterEmail,
        'time',
        'edit',
      ].join(' ').toLowerCase(),
    );
  }

  factory _UnifiedRequest.clock(ClockRequest clock) {
    return _UnifiedRequest._(
      clock: clock,
      status: clock.status,
      createdAt: clock.createdAt ?? clock.requestedAt,
      sortKey: clock.workDate,
      companyId: clock.companyId,
      companyDocumentId: clock.companyDocumentId,
      companyName: clock.companyName,
      searchText: [
        clock.username,
        clock.userEmail,
        clock.companyName,
        clock.typeLabel,
        clock.workDate,
        'clock',
        'time in',
        'time out',
      ].join(' ').toLowerCase(),
    );
  }

  final LeaveRequest? leave;
  final TimeCardChangeRequest? timeEdit;
  final ClockRequest? clock;
  final String status;
  final DateTime? createdAt;
  final String sortKey;
  final String searchText;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'approved':
      return AppColors.success;
    case 'rejected':
      return AppColors.error;
    default:
      return const Color(0xFFD97706);
  }
}

String _statusLabel(String status) {
  if (status.isEmpty) return 'Pending';
  return '${status[0].toUpperCase()}${status.substring(1)}';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final density = CompactPageStyle.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: density.compact ? 8 : 10,
        vertical: density.compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _statusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: density.chipLabelSize,
            ),
      ),
    );
  }
}

class _RequestActions extends StatelessWidget {
  const _RequestActions({
    required this.onApprove,
    required this.onReject,
  });

  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    if (onApprove == null && onReject == null) {
      return const SizedBox.shrink();
    }
    final density = CompactPageStyle.of(context);
    return Padding(
      padding: EdgeInsets.only(top: density.cardGap + 2),
      child: Row(
        children: [
          if (onReject != null)
            Expanded(
              child: OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  visualDensity: density.compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: EdgeInsets.symmetric(
                    vertical: density.compact ? 8 : 12,
                  ),
                  textStyle: TextStyle(
                    fontSize: density.bodySize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Reject'),
              ),
            ),
          if (onReject != null && onApprove != null)
            SizedBox(width: density.cardGap + 2),
          if (onApprove != null)
            Expanded(
              child: FilledButton(
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  visualDensity: density.compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    vertical: density.compact ? 8 : 12,
                  ),
                  textStyle: TextStyle(
                    fontSize: density.bodySize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Approve'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClockRequestCard extends StatelessWidget {
  const _ClockRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    this.highlighted = false,
    this.awaitingTimeInApproval = false,
    this.showUnlock = false,
    this.onUnlock,
  });

  final ClockRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool highlighted;
  final bool awaitingTimeInApproval;
  final bool showUnlock;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final name = request.username.isEmpty ? 'Employee' : request.username;
    final email = request.userEmail.isEmpty ? '—' : request.userEmail;
    final company =
        request.companyName.isEmpty ? 'Unknown company' : request.companyName;
    final when = request.requestedAt.toLocal();
    final stamp = formatDateTime12h(when);
    final todayKey = formatWorkDate(DateTime.now());
    final isPastWorkDate = request.workDate.compareTo(todayKey) < 0;

    return Container(
      margin: EdgeInsets.only(bottom: density.cardGap),
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(
          color: highlighted ? AppColors.primaryDark : colors.border,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'From notification',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.typeLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: density.chipLabelSize,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: density.cardTitleSize,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: density.chipLabelSize,
                          ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          SizedBox(height: density.cardGap),
          Text(
            company,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: density.bodySize,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Work date ${request.workDate}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: density.chipLabelSize,
                ),
          ),
          Text(
            'Requested time $stamp',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: density.captionSize,
                ),
          ),
          if (request.note.trim().isNotEmpty) ...[
            SizedBox(height: density.cardGap),
            Text(
              'Note: ${request.note.trim()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: density.captionSize,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          if (isPastWorkDate && request.awaitsReview) ...[
            SizedBox(height: density.cardGap),
            Text(
              'Past work date — you can still approve or decline this request.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: density.captionSize,
                  ),
            ),
          ],
          if (awaitingTimeInApproval) ...[
            SizedBox(height: density.cardGap),
            Text(
              'Approve time in for this day first, then approve time out.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: density.captionSize,
                  ),
            ),
          ],
          if (showUnlock && onUnlock != null) ...[
            SizedBox(height: density.cardGap),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Unlock clock requests'),
              ),
            ),
          ],
          _RequestActions(onApprove: onApprove, onReject: onReject),
        ],
      ),
    );
  }
}

class _LeaveRequestCard extends StatelessWidget {
  const _LeaveRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    this.highlighted = false,
  });

  final LeaveRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final name = request.username.isEmpty ? 'Employee' : request.username;
    final email = request.userEmail.isEmpty ? '—' : request.userEmail;
    final company =
        request.companyName.isEmpty ? 'Unknown company' : request.companyName;

    return Container(
      margin: EdgeInsets.only(bottom: density.cardGap),
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(
          color: highlighted
              ? AppColors.primaryDark
              : colors.border,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'From notification',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Leave request',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: density.chipLabelSize,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: density.cardTitleSize,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: density.chipLabelSize,
                          ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          SizedBox(height: density.cardGap),
          Text(
            company,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: density.bodySize,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '${request.startDate} → ${request.endDate}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: density.chipLabelSize,
                ),
          ),
          if (request.createdAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Requested ${_formatRequestWhen(request.createdAt!)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: density.chipLabelSize,
                  ),
            ),
          ],
          if (request.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              request.reason.trim(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          _RequestActions(onApprove: onApprove, onReject: onReject),
        ],
      ),
    );
  }

  String _formatRequestWhen(DateTime value) => formatDateTime12h(value);
}

class _TimeEditRequestCard extends StatelessWidget {
  const _TimeEditRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    this.highlighted = false,
  });

  final TimeCardChangeRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final employee =
        request.employeeName.isEmpty ? 'Employee' : request.employeeName;
    final company =
        request.companyName.isEmpty ? 'Unknown company' : request.companyName;
    final requester =
        request.requesterName.isEmpty ? 'Admin' : request.requesterName;

    return Container(
      margin: EdgeInsets.only(bottom: density.cardGap),
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(
          color: highlighted ? AppColors.primaryDark : colors.border,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'From notification',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time card change',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: density.chipLabelSize,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      employee,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: density.cardTitleSize,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      request.employeeEmail.isEmpty
                          ? '—'
                          : request.employeeEmail,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: density.chipLabelSize,
                          ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          SizedBox(height: density.cardGap),
          Text(
            company,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: density.bodySize,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Requested by $requester',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontSize: density.chipLabelSize,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Date: ${request.workDate}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Current: ${request.hasPriorRecord ? '${request.currentTimeInLabel} → ${request.currentTimeOutLabel}' : 'No prior record'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontSize: density.chipLabelSize,
                ),
          ),
          Text(
            'Proposed: ${request.proposedTimeInLabel} → ${request.proposedTimeOutLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
          ),
          if (request.note.trim().isNotEmpty) ...[
            SizedBox(height: density.cardGap),
            Text(
              'Note: ${request.note.trim()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: density.captionSize,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          _RequestActions(onApprove: onApprove, onReject: onReject),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: density.compact ? 22 : 26,
        horizontal: density.compact ? 12 : 16,
      ),
      decoration: compactCardDecoration(context),
      child: Column(
        children: [
          Icon(
            icon,
            size: density.compact ? 26 : 30,
            color: colors.textSecondary,
          ),
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

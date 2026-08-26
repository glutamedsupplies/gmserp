import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/announcement.dart';
import '../../models/company_model.dart';
import '../../models/staff_assignment.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../services/announcement_repository.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/lazy_list_pager.dart';
import '../../widgets/primary_button.dart';

class SuperAdminAnnouncementsScreen extends StatefulWidget {
  const SuperAdminAnnouncementsScreen({super.key});

  @override
  State<SuperAdminAnnouncementsScreen> createState() =>
      _SuperAdminAnnouncementsScreenState();
}

class _SuperAdminAnnouncementsScreenState
    extends State<SuperAdminAnnouncementsScreen> {
  final _repo = AnnouncementRepository();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  late final LazyListPager _pager;

  String? _companyId;
  AnnouncementAudience _audience = AnnouncementAudience.everyone;
  final Set<String> _specificIds = {};
  List<Announcement> _sent = [];
  bool _loadingStaff = false;
  bool _loadingHistory = true;
  bool _sending = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _pager = LazyListPager(onChanged: () {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final companies = context.read<CompanyProvider>();
      await companies.loadCompanies();
      await _loadHistory();
      if (!mounted) return;
      if (companies.companies.isNotEmpty && _companyId == null) {
        await _selectCompany(companies.companies.first.id);
      }
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
      _pager.reset();
    });
    try {
      final items = await _repo.listAll();
      if (!mounted) return;
      setState(() {
        _sent = items;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sent = [];
        _loadingHistory = false;
        _historyError = 'Unable to load sent announcements.';
      });
    }
  }

  Future<void> _selectCompany(String companyId) async {
    setState(() {
      _companyId = companyId;
      _specificIds.clear();
      _loadingStaff = true;
    });
    await context.read<CompanyProvider>().loadCompanyUsers(companyId);
    if (!mounted) return;
    setState(() => _loadingStaff = false);
  }

  CompanyModel? _company(CompanyProvider companies) {
    final id = _companyId;
    if (id == null) return null;
    for (final item in companies.companies) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<StaffAssignment> _companyStaff(CompanyProvider companies) {
    final members = [...companies.staff]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    return members.where((member) {
      final role = companies.memberAccessRole(member);
      return role == UserRole.admin || role == UserRole.employee;
    }).toList();
  }

  List<String> _resolveRecipients(CompanyProvider companies) {
    final staff = _companyStaff(companies);
    switch (_audience) {
      case AnnouncementAudience.companyAdmins:
        return [
          for (final member in staff)
            if (companies.memberAccessRole(member) == UserRole.admin)
              member.userId,
        ];
      case AnnouncementAudience.everyone:
        return [for (final member in staff) member.userId];
      case AnnouncementAudience.specific:
        return _specificIds.toList();
    }
  }

  List<String> _audienceOptions() =>
      [for (final option in AnnouncementAudience.values) option.label];

  String _audienceDropdownValue() => _audience.label;

  void _onAudienceChanged(String label) {
    final next = AnnouncementAudience.values.firstWhere(
      (option) => option.label == label,
      orElse: () => AnnouncementAudience.everyone,
    );
    setState(() {
      _audience = next;
      if (next != AnnouncementAudience.specific) {
        _specificIds.clear();
      }
    });
  }

  String _memberPickerLabel(
    StaffAssignment member,
    CompanyProvider companies,
  ) {
    final name =
        member.username.isEmpty ? member.email : member.username;
    final access = companies.memberAccessRole(member).label;
    return '$name · $access';
  }

  StaffAssignment? _memberFromPickerLabel(
    String label,
    List<StaffAssignment> staff,
    CompanyProvider companies,
  ) {
    for (final member in staff) {
      if (_memberPickerLabel(member, companies) == label) return member;
    }
    return null;
  }

  List<String> _memberPickerItems(
    List<StaffAssignment> staff,
    CompanyProvider companies,
  ) {
    final available = staff
        .where((member) => !_specificIds.contains(member.userId))
        .map((member) => _memberPickerLabel(member, companies))
        .toList();
    if (available.isEmpty) {
      return const ['All members selected'];
    }
    return [_memberPickerValue(), ...available];
  }

  String _memberPickerValue() {
    if (_specificIds.isEmpty) return 'Choose member';
    if (_specificIds.length == 1) return '1 member selected';
    return '${_specificIds.length} members selected';
  }

  void _onMemberPickerChanged(
    String label,
    List<StaffAssignment> staff,
    CompanyProvider companies,
  ) {
    if (label == _memberPickerValue() || label == 'All members selected') {
      return;
    }
    final member = _memberFromPickerLabel(label, staff, companies);
    if (member == null) return;
    setState(() => _specificIds.add(member.userId));
  }

  List<StaffAssignment> _selectedMembers(
    List<StaffAssignment> staff,
  ) {
    return staff.where((member) => _specificIds.contains(member.userId)).toList();
  }

  Future<void> _send() async {
    final auth = context.read<AuthProvider>().user;
    final companies = context.read<CompanyProvider>();
    final company = _company(companies);
    if (auth == null) return;
    if (company == null) {
      SnackBarHelper.showInfo(context, 'Select a company first.');
      return;
    }

    final recipients = _resolveRecipients(companies);
    if (recipients.isEmpty) {
      SnackBarHelper.showInfo(
        context,
        _audience == AnnouncementAudience.specific
            ? 'Select at least one admin or employee.'
            : 'No matching members in this company.',
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await _repo.create(
        companyId: company.id,
        companyDocumentId: company.firestoreId,
        companyName: company.name,
        audience: _audience,
        recipientIds: recipients,
        subject: _subjectController.text,
        message: _messageController.text,
        actorId: auth.id,
        actorName: auth.username.isNotEmpty ? auth.username : auth.email,
      );
      if (!mounted) return;
      _subjectController.clear();
      _messageController.clear();
      setState(() {
        _specificIds.clear();
        _sending = false;
      });
      SnackBarHelper.showSuccess(
        context,
        'Announcement sent to ${recipients.length} '
        '${recipients.length == 1 ? 'person' : 'people'}.',
      );
      await _loadHistory();
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      SnackBarHelper.showError(
        context,
        error is StateError
            ? error.message
            : 'Could not send the announcement.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final density = CompactPageStyle.of(context);
    final colors = AppColors.of(context);
    final company = _company(companies);
    final staff = company == null ? <StaffAssignment>[] : _companyStaff(companies);
    final recipientCount = company == null ? 0 : _resolveRecipients(companies).length;
    final visibleHistory = _pager.takeVisible(_sent);
    final hasMoreHistory = _pager.hasMore(_sent.length);

    return DashboardScaffold(
      title: 'Announcements',
      currentRoute: AppRoutes.superAdminAnnouncements,
      child: ListView(
        controller: _pager.scrollController,
        padding: density.pagePadding,
        children: [
          const CompactPageHeader(
            title: 'Create announcement',
            subtitle:
                'Choose a company and audience, then send a subject and message to their Notifications.',
          ),
          SizedBox(height: density.sectionGap),
          if (companies.companies.isEmpty)
            const _HintCard(
              icon: Icons.business_outlined,
              message: 'Create a company first before sending announcements.',
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: CompactFilterDropdown(
                    value: company?.name ?? companies.companies.first.name,
                    items: [for (final item in companies.companies) item.name],
                    hint: 'Company',
                    onChanged: (name) {
                      for (final item in companies.companies) {
                        if (item.name == name) {
                          _selectCompany(item.id);
                          break;
                        }
                      }
                    },
                  ),
                ),
                SizedBox(width: density.cardGap),
                Expanded(
                  child: CompactFilterDropdown(
                    value: _audienceDropdownValue(),
                    items: _audienceOptions(),
                    hint: 'Audience',
                    onChanged: _onAudienceChanged,
                  ),
                ),
              ],
            ),
            if (_audience == AnnouncementAudience.specific) ...[
              SizedBox(height: density.cardGap),
              if (_loadingStaff)
                const AppLoadingView(
                  title: 'Loading members',
                  message: 'Fetching company staff…',
                )
              else if (staff.isEmpty)
                const _HintCard(
                  icon: Icons.groups_outlined,
                  message: 'No admins or employees in this company yet.',
                )
              else ...[
                CompactFilterDropdown(
                  value: _memberPickerValue(),
                  items: _memberPickerItems(staff, companies),
                  hint: 'Member',
                  onChanged: (label) =>
                      _onMemberPickerChanged(label, staff, companies),
                ),
                if (_selectedMembers(staff).isNotEmpty) ...[
                  SizedBox(height: density.cardGap),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final member in _selectedMembers(staff))
                        InputChip(
                          label: Text(
                            _memberPickerLabel(member, companies),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontSize: density.chipLabelSize),
                          ),
                          onDeleted: () => setState(
                            () => _specificIds.remove(member.userId),
                          ),
                          deleteIconColor: colors.textSecondary,
                          visualDensity: VisualDensity.compact,
                        ),
                      ActionChip(
                        label: const Text('Clear all'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _specificIds.clear()),
                      ),
                    ],
                  ),
                ],
              ],
            ],
            SizedBox(height: density.sectionGap),
            CustomTextField(
              controller: _subjectController,
              label: 'Subject',
              hint: 'Announcement subject',
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: density.cardGap),
            Text(
              'Message',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: density.cardTitleSize,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            SizedBox(height: density.compact ? 6 : 8),
            TextField(
              controller: _messageController,
              minLines: 4,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: density.bodySize,
                  ),
              decoration: InputDecoration(
                hintText: 'Write the announcement message…',
                filled: true,
                fillColor: colors.inputFill,
                isDense: density.compact,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: density.compact ? 12 : 14,
                  vertical: density.compact ? 10 : 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(density.radius),
                ),
              ),
            ),
            SizedBox(height: density.sectionGap),
            Text(
              recipientCount == 0
                  ? 'No recipients selected'
                  : 'Will notify $recipientCount '
                      '${recipientCount == 1 ? 'person' : 'people'}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            SizedBox(height: density.cardGap),
            PrimaryButton(
              label: _sending ? 'Sending…' : 'Send announcement',
              onPressed: _sending || company == null ? null : _send,
            ),
            SizedBox(height: density.sectionGap + 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sent announcements',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loadingHistory ? null : _loadHistory,
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.primaryDark,
                ),
              ],
            ),
            SizedBox(height: density.cardGap),
            if (_loadingHistory)
              const AppLoadingView(
                title: 'Loading history',
                message: 'Fetching sent announcements…',
              )
            else if (_historyError != null)
              _HintCard(icon: Icons.error_outline, message: _historyError!)
            else if (_sent.isEmpty)
              const _HintCard(
                icon: Icons.campaign_outlined,
                message: 'No announcements sent yet.',
              )
            else ...[
              for (final item in visibleHistory) _HistoryCard(item: item),
              LazyListFooter(
                hasMore: hasMoreHistory,
                remaining: _sent.length - visibleHistory.length,
                loadingMore: _pager.loadingMore,
                onLoadMore: () => _pager.loadMore(_sent.length),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});

  final Announcement item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: density.cardGap),
      padding: density.cardPadding,
      decoration: compactCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Chip(label: item.audience.label, color: AppColors.primaryDark),
              _Chip(
                label: '${item.recipientIds.length} recipients',
                color: colors.textSecondary,
              ),
            ],
          ),
          SizedBox(height: density.titleSubtitleGap),
          Text(
            item.subject,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (item.companyName.isNotEmpty) ...[
            SizedBox(height: density.compact ? 2 : 4),
            Text(
              item.companyName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          SizedBox(height: density.titleSubtitleGap),
          Text(
            item.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

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

class _HintCard extends StatelessWidget {
  const _HintCard({required this.icon, required this.message});

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

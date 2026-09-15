import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/firebase_data.dart';
import '../core/utils/realtime_page.dart';
import '../models/announcement.dart';
import '../models/time_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/company_provider.dart';
import '../services/announcement_repository.dart';

/// Persistent announcement cards on the company landing page.
class DashboardAnnouncements extends StatefulWidget {
  const DashboardAnnouncements({super.key});

  @override
  State<DashboardAnnouncements> createState() => _DashboardAnnouncementsState();
}

class _DashboardAnnouncementsState extends State<DashboardAnnouncements>
    with RealtimePage {
  final _repository = AnnouncementRepository();
  bool _loading = true;
  bool _failed = false;
  List<Announcement> _items = [];
  String? _session;
  int _generation = 0;

  @override
  List<String> get realtimePaths => const ['announcements'];
  @override
  Duration? get desktopRefreshInterval => const Duration(seconds: 15);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<AuthProvider>().user;
    final companies = context.watch<CompanyProvider>();
    final company = companies.selectedCompany;
    final session =
        user != null && company != null && companies.hasActiveCompanySession
        ? '${user.id}:${company.firestoreId}'
        : null;
    if (_session == session) return;
    _session = session;
    _generation++;
    _items = [];
    _loading = session != null;
    _failed = false;
    if (session != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refreshRealtimeData();
      });
    }
  }

  @override
  Future<void> refreshRealtimeData() async {
    if (_session == null) return;
    final generation = ++_generation;
    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null || company == null) return;
    try {
      final items = await _repository.listForRecipient(user.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = false;
        _items = items
            .where(
              (item) => matchesCompanyRef(
                storedCompanyId: item.companyId,
                storedDocumentId: item.companyDocumentId,
                companyId: company.id,
                companyDocumentId: company.firestoreId,
              ),
            )
            .toList();
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Announcements',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Refresh announcements',
                onPressed: refreshRealtimeData,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(),
          if (_failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Could not refresh announcements. Use the refresh button to try again.',
                style: TextStyle(color: colors.error),
              ),
            ),
          if (!_loading && !_failed && _items.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No announcements for you yet.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          for (final item in _items)
            AnnouncementDashboardCard(announcement: item),
        ],
      ),
    );
  }
}

class AnnouncementDashboardCard extends StatelessWidget {
  const AnnouncementDashboardCard({super.key, required this.announcement});
  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final item = announcement;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    item.audience == AnnouncementAudience.specific
                        ? 'For you'
                        : item.audience.label,
                  ),
                ),
                Chip(label: Text(item.companyName)),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              item.subject,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              item.createdAt == null
                  ? 'Announcement time unavailable'
                  : 'Announced ${formatDateTime12h(item.createdAt!, withSeconds: true)}',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            if (item.actorName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'From: ${item.actorName}',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
            const Divider(height: 28),
            SelectableText(
              item.message,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

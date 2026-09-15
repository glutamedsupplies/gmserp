import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/firebase_data.dart';
import '../core/utils/rtdb_platform.dart';
import '../services/rtdb/rtdb_service.dart';
import '../services/announcement_live_updates.dart';
import '../models/announcement.dart';
import '../models/time_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/company_provider.dart';
import '../services/announcement_repository.dart';
import '../services/announcement_read_store.dart';

/// Shows unread announcements and persists each acknowledgement.
class CompanyAnnouncementOverlay extends StatefulWidget {
  const CompanyAnnouncementOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<CompanyAnnouncementOverlay> createState() =>
      _CompanyAnnouncementOverlayState();
}

class _CompanyAnnouncementOverlayState
    extends State<CompanyAnnouncementOverlay> {
  final _repository = AnnouncementRepository();
  final _readStore = AnnouncementReadStore();
  final _dismissed = <String>{};
  final _deferred = <String>{};
  List<Announcement> _items = [];
  String? _session;
  int _generation = 0;

  AnnouncementLiveUpdates? _updates;
  late final AppLifecycleListener _lifecycle;
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => _updates?.requestRefresh(),
    );
  }

  @override
  void dispose() {
    _updates?.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

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
    _updates?.dispose();
    _updates = null;
    _session = session;
    _generation++;
    _items = [];
    _dismissed.clear();
    _deferred.clear();
    if (session != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _session != session) return;
        _updates = AnnouncementLiveUpdates(
          changes: preferRtdbPolling
              ? const Stream<void>.empty()
              : RtdbService().watchChanges([
                  'announcements',
                  'announcementReads/${user!.id}',
                ]),
          refresh: refreshRealtimeData,
          retryInterval: Duration(seconds: preferRtdbPolling ? 2 : 15),
        )..start();
      });
    }
  }

  Future<void> refreshRealtimeData() async {
    if (_session == null) return;
    final generation = ++_generation;
    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null || company == null) return;
    try {
      RtdbService.clearReadCache();
      final items = await _repository.listForRecipient(user.id);
      final read = await _readStore.load(user.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _dismissed.addAll(read);
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
      // Preserve the last successful result and retry on the next refresh.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items
        .where(
          (item) =>
              !_dismissed.contains(item.id) && !_deferred.contains(item.id),
        )
        .toList();
    return CompanyAnnouncementPresentation(
      pending: pending,
      onDismiss: (id) async {
        final userId = context.read<AuthProvider>().user?.id;
        final session = _session;
        if (userId == null) return;
        setState(() {
          _deferred.addAll(pending.map((item) => item.id));
        });
        try {
          await _readStore.markRead(userId, id);
          if (mounted && session == _session) {
            setState(() => _dismissed.add(id));
          }
        } catch (_) {
          // Allow another acknowledgement attempt if local persistence fails.
          if (mounted && session == _session) {
            setState(() => _deferred.remove(id));
          }
        }
      },
      child: widget.child,
    );
  }
}

/// Supplies an overlay even when hosted above the app's Navigator.
class CompanyAnnouncementPresentation extends StatelessWidget {
  const CompanyAnnouncementPresentation({
    super.key,
    required this.pending,
    required this.onDismiss,
    required this.child,
  });

  final List<Announcement> pending;
  final ValueChanged<String> onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final item = pending.isEmpty ? null : pending.first;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF087F75),
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    return Overlay.wrap(
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (item != null) ...[
            const ModalBarrier(dismissible: false, color: Colors.black54),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Semantics(
                      scopesRoute: true,
                      explicitChildNodes: true,
                      namesRoute: true,
                      label: 'Company announcement',
                      child: Material(
                        color: dark
                            ? const Color(0xFF182C30)
                            : const Color(0xFFF7FCFB),
                        elevation: 12,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'For you, by ${item.companyName}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Announced from: ${item.createdAt == null ? 'Time unavailable' : formatDateTime12h(item.createdAt!, withSeconds: true)}',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'From: ${item.actorName.trim().isEmpty ? 'Superadmin' : item.actorName}',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 20),
                              SelectableText(
                                item.subject,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colors.onSurface,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                item.message,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w400,
                                      height: 1.45,
                                      color: colors.onSurface,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  FilledButton(
                                    onPressed: () => onDismiss(item.id),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colors.primary,
                                      foregroundColor: colors.onPrimary,
                                      minimumSize: const Size(96, 44),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Okay'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

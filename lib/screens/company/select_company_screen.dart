import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/app_navigator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/password_field.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/user_avatar.dart';

class SelectCompanyScreen extends StatefulWidget {
  const SelectCompanyScreen({super.key});

  @override
  State<SelectCompanyScreen> createState() => _SelectCompanyScreenState();
}

class _SelectCompanyScreenState extends State<SelectCompanyScreen> {
  final _pageController = PageController(viewportFraction: 0.84);
  int _index = 0;
  bool _opening = false;
  bool _didSyncPage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = context.read<AuthProvider>().user;
      final companies = context.read<CompanyProvider>();
      if (user != null) {
        await companies.loadCompaniesForMember(user);
      }
      if (mounted) _syncToCurrentCompany();
    });
  }

  void _syncToCurrentCompany() {
    if (_didSyncPage) return;
    final companies = context.read<CompanyProvider>();
    final currentId = companies.selectedCompany?.id;
    if (currentId == null) return;
    final index = companies.memberCompanies.indexWhere((item) => item.id == currentId);
    if (index < 0) return;
    _didSyncPage = true;
    _index = index;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }
    setState(() {});
  }

  void _returnToDashboard() {
    context.read<CompanyProvider>().endCompanyPick();
    AppNavigator.popToRoot(context);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _unlockAndGo(CompanyModel company, String code) async {
    final companies = context.read<CompanyProvider>();
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    final isMember = await companies.isCompanyMember(
      companyId: company.id,
      userId: user.id,
      email: user.email,
    );
    if (!mounted) return;
    if (!isMember) {
      SnackBarHelper.showError(
        context,
        'You have not been added to ${company.name}.',
      );
      return;
    }

    setState(() => _opening = true);
    SnackBarHelper.showLoading(
      context,
      title: 'Opening company',
      message: 'Unlocking ${company.name}…',
    );
    final ok = await companies.unlockCompanyById(
      companyId: company.id,
      password: code,
      fallback: company,
    );
    SnackBarHelper.hideLoading();
    if (!mounted) return;
    if (!ok) {
      setState(() => _opening = false);
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Incorrect company code.',
      );
      return;
    }

    SnackBarHelper.showSuccess(context, 'Opened ${company.name}.');
    AppNavigator.popToRoot(context);
  }

  Future<void> _openCompany(CompanyModel company) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _CompanyCodeSheet(company: company),
    );

    if (code == null || !mounted) return;
    await _unlockAndGo(company, code);
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final items = companies.memberCompanies;
    final index = items.isEmpty ? 0 : _index.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[index];
    final canGoBack = companies.selectedCompany != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !canGoBack) return;
        _returnToDashboard();
      },
      child: Scaffold(
        backgroundColor: AppColors.of(context).background,
        body: Column(
          children: [
            _LockedSelectHeader(
              onBack: canGoBack ? _returnToDashboard : null,
            ),
            Expanded(
              child: companies.isLoading
                  ? const AppLoadingView(
                      title: 'Loading companies',
                      message: 'Fetching your company list…',
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: CompactPageStyle.of(context).pagePaddingTopOnly,
                          child: Column(
                            children: [
                              Text(
                                'Choose a company',
                                textAlign: TextAlign.center,
                                style: (CompactPageStyle.of(context).compact
                                        ? Theme.of(context).textTheme.titleLarge
                                        : Theme.of(context)
                                            .textTheme
                                            .headlineMedium)
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              SizedBox(
                                height:
                                    CompactPageStyle.of(context).titleSubtitleGap,
                              ),
                              Text(
                                canGoBack
                                    ? 'Pick another company, or go back to the current one.'
                                    : 'Swipe to pick a company, then continue to the dashboard.',
                                textAlign: TextAlign.center,
                                style: (CompactPageStyle.of(context).compact
                                        ? Theme.of(context).textTheme.bodySmall
                                        : Theme.of(context)
                                            .textTheme
                                            .bodyMedium)
                                    ?.copyWith(
                                  color: AppColors.of(context).textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: items.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'No companies are available yet. Ask a Super Admin to add you as an employee first.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                )
                              : PageView.builder(
                                  controller: _pageController,
                                  itemCount: items.length,
                                  onPageChanged: (page) {
                                    setState(() => _index = page);
                                  },
                                  itemBuilder: (context, itemIndex) {
                                    final company = items[itemIndex];
                                    final active = itemIndex == index;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 20,
                                      ),
                                      child: AnimatedScale(
                                        scale: active ? 1 : 0.94,
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        child: _CompanyCarouselCard(
                                          company: company,
                                          logoBytes:
                                              companies.logoFor(company.id),
                                          logoRevision:
                                              companies.logoRevision,
                                          selected: active,
                                          onTap: () => _openCompany(company),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        if (items.isNotEmpty) ...[
                          _CarouselDots(count: items.length, index: index),
                          const SizedBox(height: 16),
                        ],
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          child: PrimaryButton(
                            label: 'Continue',
                            isLoading: _opening,
                            onPressed: selected == null || _opening
                                ? null
                                : () => _openCompany(selected),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedSelectHeader extends StatelessWidget {
  const _LockedSelectHeader({this.onBack});

  final VoidCallback? onBack;

  Future<void> _logout(BuildContext context) async {
    SnackBarHelper.showLoading(
      context,
      title: 'Signing out',
      message: 'Ending your session…',
    );
    context.read<CompanyProvider>().clearSelection();
    await context.read<AuthProvider>().logout();
    SnackBarHelper.hideLoading();
    if (!context.mounted) return;
    SnackBarHelper.showInfo(context, 'You have been signed out.');
    AppNavigator.popToRoot(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final role = context.watch<AuthProvider>().user?.role.label;

    return Material(
      color: colors.header,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: density.headerPadding,
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: colors.textPrimary,
                ),
              SizedBox(
                width: density.headerLogoSize,
                height: density.headerLogoSize,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Image.asset('assets/branding/gmserp_logo.png'),
                ),
              ),
              SizedBox(width: density.compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select company',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: density.headerTitleSize,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (role != null)
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: density.compact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          color: colors.sidebarMuted,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _logout(context),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyCarouselCard extends StatelessWidget {
  const _CompanyCarouselCard({
    required this.company,
    required this.logoBytes,
    required this.logoRevision,
    required this.selected,
    required this.onTap,
  });

  final CompanyModel company;
  final Uint8List? logoBytes;
  final int logoRevision;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardRadius = density.compact ? 20.0 : 28.0;

    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: dark ? 0.18 : 0.22)
          : colors.inputFill,
      borderRadius: BorderRadius.circular(cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(cardRadius),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cardRadius),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.7)
                  : colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: density.compact
                ? const EdgeInsets.fromLTRB(18, 18, 18, 16)
                : const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    UserAvatar(
                      key: ValueKey('${company.id}-$logoRevision'),
                      bytes: logoBytes,
                      name: company.name,
                      size: density.compact ? 80 : 96,
                    ),
                    SizedBox(height: density.sectionGap + 6),
                    Text(
                      company.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (density.compact
                              ? Theme.of(context).textTheme.titleLarge
                              : Theme.of(context).textTheme.headlineMedium)
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: density.cardGap),
                    Text(
                      'COMPANY ID: ${company.companyId}',
                      textAlign: TextAlign.center,
                      style: density.compact
                          ? Theme.of(context).textTheme.bodySmall
                          : Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: density.sectionGap),
                    Text(
                      selected ? 'Selected' : 'Swipe to choose',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CarouselDots extends StatelessWidget {
  const _CarouselDots({
    required this.count,
    required this.index,
  });

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (itemIndex) {
        final active = itemIndex == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : colors.border,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}

class _CompanyCodeSheet extends StatefulWidget {
  const _CompanyCodeSheet({required this.company});

  final CompanyModel company;

  @override
  State<_CompanyCodeSheet> createState() => _CompanyCodeSheetState();
}

class _CompanyCodeSheetState extends State<_CompanyCodeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _codeController.text);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.of(context).border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.company.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the company code to open this company.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            PasswordField(
              controller: _codeController,
              label: 'Company code',
              hint: 'Code shared with employees',
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Company code is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Open company',
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';

/// Density tokens for in-app chrome and pages (compact vs normal).
class CompactPageStyle {
  const CompactPageStyle._(this.compact);

  final bool compact;

  /// Density tokens for the current settings.
  ///
  /// Always non-listening so it is safe in build *and* in cancel/dismiss
  /// callbacks (sheet/dialog openers). Rebuilds when density changes are
  /// driven by ancestors that [watch] [SettingsProvider] (see [App] /
  /// [DashboardScaffold]).
  static CompactPageStyle of(BuildContext context) => read(context);

  /// Non-listening lookup for callbacks / one-shot reads.
  static CompactPageStyle read(BuildContext context) {
    final compact = context.read<SettingsProvider>().isCompactMode;
    return CompactPageStyle._(compact);
  }

  EdgeInsets get pagePadding => compact
      ? const EdgeInsets.fromLTRB(16, 16, 16, 20)
      : const EdgeInsets.fromLTRB(20, 20, 20, 24);

  EdgeInsets get pagePaddingTopOnly => compact
      ? const EdgeInsets.fromLTRB(16, 16, 16, 0)
      : const EdgeInsets.fromLTRB(20, 20, 20, 0);

  EdgeInsets get listPadding => compact
      ? const EdgeInsets.fromLTRB(16, 0, 16, 20)
      : const EdgeInsets.fromLTRB(20, 0, 20, 24);

  double get radius => compact ? 8 : 12;

  double get filterHeight => compact ? 36 : 44;

  EdgeInsets get cardPadding => compact
      ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
      : const EdgeInsets.fromLTRB(14, 12, 14, 12);

  EdgeInsets get summaryPadding => compact
      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
      : const EdgeInsets.fromLTRB(12, 12, 12, 12);

  double get cardGap => compact ? 6 : 10;

  double get sectionGap => compact ? 8 : 14;

  double get titleSubtitleGap => compact ? 4 : 6;

  // App chrome (header + sidebar)
  double get sidebarExpandedWidth => compact ? 248 : 268;

  double get sidebarCollapsedWidth => compact ? 72 : 84;

  EdgeInsets get headerPadding => compact
      ? const EdgeInsets.fromLTRB(4, 4, 12, 4)
      : const EdgeInsets.fromLTRB(8, 8, 16, 8);

  double get headerTitleSize => compact ? 16 : 18;

  double get headerLogoSize => compact ? 30 : 36;

  double get sidebarAvatarSize => compact ? 36 : 44;

  double get sidebarCollapsedAvatarSize => compact ? 32 : 40;

  EdgeInsets get sidebarProfilePadding => compact
      ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
      : const EdgeInsets.fromLTRB(10, 12, 10, 8);

  EdgeInsets get sidebarNavPadding => compact
      ? const EdgeInsets.symmetric(horizontal: 8)
      : const EdgeInsets.symmetric(horizontal: 10);

  EdgeInsets get sidebarTilePadding => compact
      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
      : const EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  double get sidebarTileGap => compact ? 4 : 6;

  double get sidebarIconSize => compact ? 20 : 22;

  double get sidebarBrandSize => compact ? 14 : 16;

  double get settingsCardRadius => compact ? 10 : 18;

  EdgeInsets get settingsRowPadding => compact
      ? const EdgeInsets.fromLTRB(12, 10, 8, 10)
      : const EdgeInsets.fromLTRB(16, 12, 10, 12);

  double get settingsIconSize => compact ? 36 : 44;
}

/// Page title + optional subtitle that follows compact/normal density.
class CompactPageHeader extends StatelessWidget {
  const CompactPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: (density.compact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineMedium)
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                SizedBox(height: density.titleSubtitleGap),
                Text(
                  subtitle!,
                  style: (density.compact
                          ? Theme.of(context).textTheme.bodySmall
                          : Theme.of(context).textTheme.bodyMedium)
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

/// Dropdown shell that follows compact/normal density.
class CompactFilterDropdown extends StatelessWidget {
  const CompactFilterDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final display = items.contains(value) ? value : items.first;
    return Container(
      height: density.filterHeight,
      padding: EdgeInsets.symmetric(horizontal: density.compact ? 10 : 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: display,
          isExpanded: true,
          isDense: density.compact,
          style: density.compact
              ? Theme.of(context).textTheme.bodySmall
              : Theme.of(context).textTheme.bodyMedium,
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item,
                child: Text(
                  item == 'All' && hint != null
                      ? (hint == 'Company'
                          ? 'All companies'
                          : 'All ${hint!.toLowerCase()}s')
                      : item,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

class CompactSummaryStrip extends StatelessWidget {
  const CompactSummaryStrip({
    super.key,
    required this.items,
  });

  final List<CompactSummaryItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return Container(
      padding: density.summaryPadding,
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: Column(
                children: [
                  Text(
                    item.value,
                    style: (density.compact
                            ? Theme.of(context).textTheme.labelLarge
                            : Theme.of(context).textTheme.titleMedium)
                        ?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: item.color ?? AppColors.primaryDark,
                    ),
                  ),
                  if (!density.compact) const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: density.compact ? 10 : null,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class CompactSummaryItem {
  const CompactSummaryItem({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;
}

/// Search field that follows compact/normal density.
class CompactSearchField extends StatelessWidget {
  const CompactSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search…',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: density.compact
          ? Theme.of(context).textTheme.bodySmall
          : Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: density.compact,
        contentPadding: density.compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: density.compact ? 12 : 14,
          color: colors.textHint,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: density.compact ? 18 : 20,
          color: colors.textHint,
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: density.compact ? 36 : 40,
          minHeight: density.compact ? 32 : 40,
        ),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(density.radius),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(density.radius),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(density.radius),
          borderSide: const BorderSide(color: AppColors.borderFocused),
        ),
      ),
    );
  }
}

Decoration compactCardDecoration(BuildContext context) {
  final colors = AppColors.of(context);
  final density = CompactPageStyle.of(context);
  return BoxDecoration(
    color: colors.card,
    borderRadius: BorderRadius.circular(density.radius),
    border: Border.all(color: colors.border),
  );
}

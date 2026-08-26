import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';

/// Density tokens for in-app chrome and pages (compact vs normal).
///
/// Normal mode uses larger fonts, padding, and card radii than compact.
/// Toggle rebuilds the whole app via [SettingsProvider] + density-aware theme.
class CompactPageStyle {
  const CompactPageStyle._(this.compact);

  final bool compact;

  /// Listening lookup for build methods — rebuilds when density changes.
  static CompactPageStyle of(BuildContext context) {
    final compact = context.watch<SettingsProvider>().isCompactMode;
    return CompactPageStyle._(compact);
  }

  /// Non-listening lookup for callbacks / one-shot reads (sheets, dismiss).
  static CompactPageStyle read(BuildContext context) {
    final compact = context.read<SettingsProvider>().isCompactMode;
    return CompactPageStyle._(compact);
  }

  // —— Page layout ——
  EdgeInsets get pagePadding => compact
      ? const EdgeInsets.fromLTRB(14, 14, 14, 18)
      : const EdgeInsets.fromLTRB(22, 22, 22, 28);

  EdgeInsets get pagePaddingTopOnly => compact
      ? const EdgeInsets.fromLTRB(14, 14, 14, 0)
      : const EdgeInsets.fromLTRB(22, 22, 22, 0);

  EdgeInsets get listPadding => compact
      ? const EdgeInsets.fromLTRB(14, 0, 14, 18)
      : const EdgeInsets.fromLTRB(22, 0, 22, 28);

  double get radius => compact ? 8 : 14;

  double get filterHeight => compact ? 36 : 48;

  EdgeInsets get cardPadding => compact
      ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
      : const EdgeInsets.fromLTRB(16, 14, 16, 14);

  EdgeInsets get summaryPadding => compact
      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
      : const EdgeInsets.fromLTRB(14, 14, 14, 14);

  double get cardGap => compact ? 6 : 12;

  double get sectionGap => compact ? 8 : 16;

  double get titleSubtitleGap => compact ? 4 : 8;

  // —— Typography (use when Theme textTheme isn't enough) ——
  double get pageTitleSize => compact ? 17 : 22;

  double get sectionTitleSize => compact ? 14 : 17;

  double get cardTitleSize => compact ? 13 : 16;

  double get bodySize => compact ? 12 : 15;

  double get captionSize => compact ? 11 : 13;

  double get chipLabelSize => compact ? 10 : 12;

  // —— App chrome (header + sidebar) ——
  double get sidebarExpandedWidth => compact ? 248 : 280;

  double get sidebarCollapsedWidth => compact ? 72 : 88;

  EdgeInsets get headerPadding => compact
      ? const EdgeInsets.fromLTRB(4, 4, 12, 4)
      : const EdgeInsets.fromLTRB(10, 10, 18, 10);

  double get headerTitleSize => compact ? 16 : 20;

  double get headerLogoSize => compact ? 30 : 40;

  double get sidebarAvatarSize => compact ? 36 : 48;

  double get sidebarCollapsedAvatarSize => compact ? 32 : 42;

  EdgeInsets get sidebarProfilePadding => compact
      ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
      : const EdgeInsets.fromLTRB(12, 14, 12, 10);

  EdgeInsets get sidebarNavPadding => compact
      ? const EdgeInsets.symmetric(horizontal: 8)
      : const EdgeInsets.symmetric(horizontal: 12);

  EdgeInsets get sidebarTilePadding => compact
      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
      : const EdgeInsets.symmetric(horizontal: 14, vertical: 14);

  double get sidebarTileGap => compact ? 4 : 8;

  double get sidebarIconSize => compact ? 20 : 24;

  double get sidebarBrandSize => compact ? 14 : 17;

  double get settingsCardRadius => compact ? 10 : 18;

  EdgeInsets get settingsRowPadding => compact
      ? const EdgeInsets.fromLTRB(12, 10, 8, 10)
      : const EdgeInsets.fromLTRB(16, 14, 12, 14);

  double get settingsIconSize => compact ? 36 : 48;

  double get buttonHeight => compact ? 48 : 56;
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: density.pageTitleSize,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                SizedBox(height: density.titleSubtitleGap),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: density.bodySize,
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
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
      padding: EdgeInsets.symmetric(horizontal: density.compact ? 10 : 14),
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: density.bodySize,
                color: colors.textPrimary,
              ),
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item,
                child: Text(
                  item == 'All' && hint != null
                      ? _allLabelForHint(hint!)
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

  static String _allLabelForHint(String hint) {
    switch (hint) {
      case 'Company':
        return 'All companies';
      case 'Status':
        return 'All Status';
      default:
        final lower = hint.toLowerCase();
        if (lower.endsWith('s')) return 'All $lower';
        return 'All ${lower}s';
    }
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: density.sectionTitleSize,
                          fontWeight: FontWeight.w800,
                          color: item.color ?? AppColors.primaryDark,
                        ),
                  ),
                  SizedBox(height: density.compact ? 2 : 4),
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: density.chipLabelSize,
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
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: density.bodySize,
            color: colors.textPrimary,
          ),
      decoration: InputDecoration(
        isDense: density.compact,
        contentPadding: density.compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: density.bodySize,
          color: colors.textHint,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: density.compact ? 18 : 22,
          color: colors.textHint,
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: density.compact ? 36 : 44,
          minHeight: density.compact ? 32 : 44,
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

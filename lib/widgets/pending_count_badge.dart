import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Small count chip for sidebar / menu notification badges.
class PendingCountBadge extends StatelessWidget {
  const PendingCountBadge({
    super.key,
    required this.count,
    this.compact = false,
  });

  final int count;
  final bool compact;

  static String labelFor(int count) {
    if (count <= 0) return '';
    if (count > 99) return '99+';
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = labelFor(count);
    return Container(
      constraints: BoxConstraints(minWidth: compact ? 16 : 20),
      padding: EdgeInsets.symmetric(
        horizontal: label.length > 1 ? (compact ? 4 : 6) : (compact ? 3 : 5),
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 9 : 11,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class BadgedIcon extends StatelessWidget {
  const BadgedIcon({
    super.key,
    required this.icon,
    required this.count,
    this.iconSize = 22,
    this.color,
  });

  final IconData icon;
  final int count;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: iconSize, color: color),
        if (count > 0)
          Positioned(
            right: -8,
            top: -6,
            child: PendingCountBadge(count: count, compact: true),
          ),
      ],
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.bytes,
    required this.name,
    this.size = 40,
  });

  final Uint8List? bytes;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final fallback = ColoredBox(
      color: AppColors.primary,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.38,
          ),
        ),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: bytes == null || bytes!.isEmpty
            ? fallback
            : Image.memory(
                bytes!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final text = parts.first;
      return text.substring(0, text.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'user_avatar.dart';

class EditablePhoto extends StatelessWidget {
  const EditablePhoto({
    super.key,
    required this.bytes,
    required this.name,
    required this.onTap,
    this.onRemove,
    this.size = 96,
    this.helperText =
        'Tap to choose a photo, then crop it. Stored on this device only.',
  });

  final Uint8List? bytes;
  final String name;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final double size;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Stack(
            children: [
              UserAvatar(
                bytes: bytes,
                name: name,
                size: size,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 16,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          helperText,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (onRemove != null) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: onRemove,
            child: const Text('Remove photo'),
          ),
        ],
      ],
    );
  }
}

import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({
    super.key,
    required this.imageBytes,
  });

  final Uint8List imageBytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final _controller = CropController();
  bool _busy = false;

  void _crop() {
    if (_busy) return;
    setState(() => _busy = true);
    _controller.cropCircle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cropBackdrop,
      appBar: AppBar(
        backgroundColor: AppColors.cropBackdrop,
        foregroundColor: Colors.white,
        title: const Text('Crop photo'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _crop,
            child: const Text(
              'Done',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.imageBytes,
              controller: _controller,
              withCircleUi: true,
              aspectRatio: 1,
              interactive: true,
              baseColor: AppColors.cropBackdrop,
              maskColor: Colors.black.withValues(alpha: 0.55),
              progressIndicator: const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              onCropped: (result) {
                if (!mounted) return;
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.of(context).pop(croppedImage);
                  case CropFailure(:final cause):
                    setState(() => _busy = false);
                    SnackBarHelper.showError(
                      context,
                      'Could not crop this photo. Try another image.',
                    );
                    debugPrint('Avatar crop failed: $cause');
                }
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  const Text(
                    'Pinch to zoom, then drag to frame your photo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _crop,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Use this crop'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

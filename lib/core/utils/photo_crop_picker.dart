import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../screens/dashboard/avatar_crop_screen.dart';

Future<Uint8List?> pickAndCropPhoto(BuildContext context) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 95,
  );
  if (file == null || !context.mounted) return null;

  final original = await file.readAsBytes();
  if (!context.mounted) return null;

  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => AvatarCropScreen(imageBytes: original),
    ),
  );
}

String photoPickerErrorMessage(Object error) {
  if (error is MissingPluginException) {
    return 'Photo picker needs a full app rebuild. Stop the app and run flutter run again.';
  }
  if (error is PlatformException && error.message?.isNotEmpty == true) {
    return error.message!;
  }
  return 'Could not open the photo picker.';
}

import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> savePngBytesImpl(Uint8List bytes, String fileName) async {
  final nameWithoutExt = fileName.toLowerCase().endsWith('.png')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;

  // Phone / tablet / macOS — save into the device Photos / Gallery.
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        throw StateError('Gallery permission denied.');
      }
    }

    await Gal.putImageBytes(
      bytes,
      album: 'GMSERP',
      name: nameWithoutExt,
    );
    return 'Photos / Gallery (GMSERP album)';
  }

  // Windows / Linux — save to the user Downloads folder.
  final downloads = await getDownloadsDirectory();
  final dir = downloads ?? await getApplicationDocumentsDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

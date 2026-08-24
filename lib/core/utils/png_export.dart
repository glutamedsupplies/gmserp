import 'dart:typed_data';

import 'png_export_stub.dart'
    if (dart.library.io) 'png_export_io.dart'
    if (dart.library.html) 'png_export_web.dart';

Future<String?> savePngBytes(Uint8List bytes, String fileName) {
  return savePngBytesImpl(bytes, fileName);
}

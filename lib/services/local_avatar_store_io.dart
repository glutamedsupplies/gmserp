import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'local_avatar_store.dart';

class DeviceLocalAvatarStore implements LocalAvatarStore {
  Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/avatars');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _safeId(String userId) {
    return userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  Future<void> _deleteExisting(String userId) async {
    final dir = await _directory();
    final prefix = _safeId(userId);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name == prefix || name.startsWith('$prefix.')) {
        await entity.delete();
      }
    }
  }

  @override
  Future<Uint8List?> read(String userId) async {
    try {
      final dir = await _directory();
      final file = File('${dir.path}/${_safeId(userId)}.jpg');
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (error) {
      debugPrint('Local avatar read failed: $error');
      return null;
    }
  }

  @override
  Future<void> write(String userId, List<int> bytes) async {
    await _deleteExisting(userId);
    final dir = await _directory();
    final file = File('${dir.path}/${_safeId(userId)}.jpg');
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> delete(String userId) async {
    await _deleteExisting(userId);
  }
}

LocalAvatarStore createLocalAvatarStore() => DeviceLocalAvatarStore();

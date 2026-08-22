import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_avatar_store.dart';

class WebLocalAvatarStore implements LocalAvatarStore {
  String _key(String userId) => 'local_avatar_$userId';

  @override
  Future<Uint8List?> read(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key(userId));
    if (encoded == null || encoded.isEmpty) return null;
    return Uint8List.fromList(base64Decode(encoded));
  }

  @override
  Future<void> write(String userId, List<int> bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), base64Encode(bytes));
  }

  @override
  Future<void> delete(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }
}

LocalAvatarStore createLocalAvatarStore() => WebLocalAvatarStore();

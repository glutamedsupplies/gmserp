import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Syncs profile photos to Firebase Storage so mobile and web share the same image.
class AvatarCloudStore {
  AvatarCloudStore({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Reference _refFor(String userId) =>
      _storage.ref().child('avatars').child('$userId.png');

  Future<String> upload({
    required String userId,
    required List<int> bytes,
  }) async {
    final data = Uint8List.fromList(bytes);
    final ref = _refFor(userId);
    await ref.putData(
      data,
      SettableMetadata(
        contentType: 'image/png',
        cacheControl: 'public,max-age=3600',
      ),
    );
    return ref.getDownloadURL();
  }

  Future<void> delete(String userId) async {
    try {
      await _refFor(userId).delete();
    } on FirebaseException catch (error) {
      // Already gone is fine.
      if (error.code != 'object-not-found') rethrow;
    }
  }

  Future<Uint8List?> downloadBytes(String photoUrl) async {
    final url = photoUrl.trim();
    if (url.isEmpty) return null;
    try {
      final ref = _storage.refFromURL(url);
      return await ref.getData(5 * 1024 * 1024);
    } catch (error) {
      debugPrint('Avatar download failed: $error');
      return null;
    }
  }
}

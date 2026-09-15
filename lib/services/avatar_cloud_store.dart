import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Syncs profile photos to Firebase Storage so mobile and web share the same image.
class AvatarCloudStore {
  AvatarCloudStore({FirebaseStorage? storage}) : _providedStorage = storage;

  final FirebaseStorage? _providedStorage;
  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;

  Reference _refFor(String userId) => _storage.ref(
    'avatars/$userId/${DateTime.now().microsecondsSinceEpoch}.png',
  );

  Future<String> upload({
    required String userId,
    required List<int> bytes,
  }) async {
    final ref = _refFor(userId);
    return _upload(ref, bytes);
  }

  Future<String> uploadCompanyLogo({
    required String companyId,
    required List<int> bytes,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in again.');
    return _upload(
      _storage.ref(
        'company-logos/$uid/$companyId/${DateTime.now().microsecondsSinceEpoch}.png',
      ),
      bytes,
    );
  }

  Future<String> _upload(Reference ref, List<int> bytes) async {
    if (bytes.isEmpty || bytes.length >= 5 * 1024 * 1024) {
      throw ArgumentError('Choose a photo smaller than 5 MB.');
    }
    final data = Uint8List.fromList(bytes);
    await ref.putData(
      data,
      SettableMetadata(
        contentType: 'image/png',
        cacheControl: 'public,max-age=3600',
      ),
    );
    return ref.getDownloadURL();
  }

  Future<void> delete(String photoUrl) async {
    if (photoUrl.trim().isEmpty) return;
    try {
      await _storage.refFromURL(photoUrl).delete();
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

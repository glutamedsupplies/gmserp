import 'dart:typed_data';

abstract class LocalAvatarStore {
  Future<Uint8List?> read(String userId);
  Future<void> write(String userId, List<int> bytes);
  Future<void> delete(String userId);
}

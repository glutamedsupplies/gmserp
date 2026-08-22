import 'local_avatar_store.dart';
import 'local_avatar_store_io.dart'
    if (dart.library.html) 'local_avatar_store_web.dart' as backend;

LocalAvatarStore createLocalAvatarStore() => backend.createLocalAvatarStore();

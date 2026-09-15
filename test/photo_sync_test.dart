import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/models/company_model.dart';
import 'package:new_gmserp/models/user_model.dart';
import 'package:new_gmserp/providers/auth_provider.dart';
import 'package:new_gmserp/providers/company_provider.dart';
import 'package:new_gmserp/services/auth_service.dart';
import 'package:new_gmserp/services/avatar_cloud_store.dart';
import 'package:new_gmserp/services/company_repository.dart';
import 'package:new_gmserp/services/user_repository.dart';

class _Cloud implements AvatarCloudStore {
  final images = <String, Uint8List>{};
  bool failUpload = false;
  int revision = 0;

  Future<String> _upload(List<int> bytes) async {
    if (failUpload) throw StateError('Upload failed');
    final url = 'https://storage.test/${++revision}.png';
    images[url] = Uint8List.fromList(bytes);
    return url;
  }

  @override
  Future<String> upload({required String userId, required List<int> bytes}) =>
      _upload(bytes);

  @override
  Future<String> uploadCompanyLogo({
    required String companyId,
    required List<int> bytes,
  }) => _upload(bytes);

  @override
  Future<Uint8List?> downloadBytes(String photoUrl) async => images[photoUrl];

  @override
  Future<void> delete(String photoUrl) async {
    images.remove(photoUrl);
  }
}

class _Users implements UserRepository {
  UserModel user = const UserModel(
    id: 'u1',
    username: 'User',
    email: 'user@test.com',
    phoneNumber: '',
  );
  bool failWrite = false;

  @override
  Future<void> updatePhotoUrl({
    required String userId,
    required String? photoUrl,
  }) async {
    if (failWrite) throw StateError('Database write failed');
    user = user.copyWith(photoUrl: photoUrl);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthService {
  _Auth(this.users);
  final _Users users;
  @override
  Future<UserModel?> checkAuthentication() async => users.user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Companies implements CompanyRepository {
  String url = '';
  bool failWrite = false;
  @override
  Future<List<CompanyModel>> listCompanies() async => [
    CompanyModel(
      id: 'company',
      name: 'Company',
      passwordHash: '',
      createdBy: 'u1',
      logoUrl: url,
    ),
  ];
  @override
  Future<void> updateLogoUrl({
    required String companyId,
    required String logoUrl,
  }) async {
    if (failWrite) throw StateError('Database write failed');
    url = logoUrl;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account replacements and removals reach another device', () async {
    final users = _Users();
    final cloud = _Cloud();
    AuthProvider device() => AuthProvider(
      authService: _Auth(users),
      users: users,
      avatarCloud: cloud,
    );
    final first = device();
    final second = device();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.checkAuthentication();
    expect(await first.saveAvatar([1, 2]), isTrue);
    await second.checkAuthentication();
    expect(second.avatarBytes, [1, 2]);
    expect(await first.saveAvatar([3, 4]), isTrue);
    await second.reloadUser();
    expect(second.avatarBytes, [3, 4]);
    expect(await first.removeAvatar(), isTrue);
    await second.reloadUser();
    expect(second.avatarBytes, isNull);
  });

  test(
    'failed account upload or database write keeps the published photo',
    () async {
      final users = _Users();
      final cloud = _Cloud();
      final auth = AuthProvider(
        authService: _Auth(users),
        users: users,
        avatarCloud: cloud,
      );
      addTearDown(auth.dispose);
      await auth.checkAuthentication();
      await auth.saveAvatar([1]);
      final oldUrl = users.user.photoUrl;
      cloud.failUpload = true;
      expect(await auth.saveAvatar([2]), isFalse);
      cloud.failUpload = false;
      users.failWrite = true;
      expect(await auth.saveAvatar([3]), isFalse);
      expect(auth.avatarBytes, [1]);
      expect(users.user.photoUrl, oldUrl);
      expect(await auth.removeAvatar(), isFalse);
      expect(cloud.images[oldUrl], [1]);
    },
  );

  test('company replacements and removals reach another device', () async {
    final repo = _Companies();
    final cloud = _Cloud();
    CompanyProvider device() => CompanyProvider(
      companyRepository: repo,
      userRepository: _Users(),
      logoCloud: cloud,
    );
    final first = device();
    final second = device();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    expect(await first.saveCompanyLogo('company', [1]), isTrue);
    await second.loadCompanies();
    expect(second.logoFor('company'), [1]);
    expect(await first.saveCompanyLogo('company', [2]), isTrue);
    await second.loadCompanies();
    expect(second.logoFor('company'), [2]);
    repo.failWrite = true;
    expect(await first.saveCompanyLogo('company', [3]), isFalse);
    expect(first.logoFor('company'), [2]);
    repo.failWrite = false;
    expect(await first.removeCompanyLogo('company'), isTrue);
    await second.loadCompanies();
    expect(second.logoFor('company'), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/services/app_instance_guard_stub.dart';

void main() {
  test('stub guard always allows the primary instance', () async {
    final guard = AppInstanceGuard.instance;
    await guard.initialize();
    expect(guard.isPrimary, isTrue);
    guard.dispose();
  });
}

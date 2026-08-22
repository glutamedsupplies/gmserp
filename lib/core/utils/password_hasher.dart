import 'dart:convert';

import 'package:crypto/crypto.dart';

class PasswordHasher {
  PasswordHasher._();

  static String hash(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static bool matches({
    required String plainText,
    required String hash,
  }) {
    return PasswordHasher.hash(plainText) == hash;
  }
}

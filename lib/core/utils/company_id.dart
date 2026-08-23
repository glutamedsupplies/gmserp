import 'dart:math';

import 'package:flutter/services.dart';

class CompanyId {
  CompanyId._();

  static const int length = 8;
  static final _digitsOnly = RegExp(r'[^0-9]');
  static final _eightDigits = RegExp(r'^\d{8}$');
  static final _random = Random.secure();

  static final List<TextInputFormatter> inputFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(length),
  ];

  static String normalize(String value) {
    return value.trim().replaceAll(_digitsOnly, '');
  }

  static String generate() {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }

  static String? validate(String? value) {
    final id = normalize(value ?? '');
    if (id.isEmpty) return 'Company ID is required.';
    if (id.length != length) {
      return 'Company ID must be exactly $length digits.';
    }
    if (!_eightDigits.hasMatch(id)) {
      return 'Company ID must be $length digits only.';
    }
    return null;
  }
}

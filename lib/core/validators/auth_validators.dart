class AuthValidators {
  AuthValidators._();

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// Accepts 09XXXXXXXXX or +639XXXXXXXXX
  static final RegExp _phPhoneRegex = RegExp(
    r'^(09\d{9}|\+639\d{9})$',
  );

  static final RegExp _upperCase = RegExp(r'[A-Z]');
  static final RegExp _lowerCase = RegExp(r'[a-z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _special = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/]');

  static String? username(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Username is required.';
    }
    if (text.length < 3) {
      return 'Username must be at least 3 characters.';
    }
    if (text.length > 30) {
      return 'Username must be at most 30 characters.';
    }
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Email is required.';
    }
    if (!_emailRegex.hasMatch(text)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  static String? phoneNumber(String? value) {
    final text = value?.trim().replaceAll(' ', '') ?? '';
    if (text.isEmpty) {
      return 'Phone number is required.';
    }
    if (!_phPhoneRegex.hasMatch(text)) {
      return 'Please enter a valid Philippine phone number.';
    }
    return null;
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) {
      return 'Password is required.';
    }
    if (text.length < 8) {
      return 'Password must contain at least 8 characters.';
    }
    if (!_upperCase.hasMatch(text)) {
      return 'Password must contain an uppercase letter.';
    }
    if (!_lowerCase.hasMatch(text)) {
      return 'Password must contain a lowercase letter.';
    }
    if (!_digit.hasMatch(text)) {
      return 'Password must contain a number.';
    }
    if (!_special.hasMatch(text)) {
      return 'Password must contain a special character.';
    }
    return null;
  }

  static String? loginPassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) {
      return 'Password is required.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final text = value ?? '';
    if (text.isEmpty) {
      return 'Please confirm your password.';
    }
    if (text != password) {
      return 'Passwords do not match.';
    }
    return null;
  }
}

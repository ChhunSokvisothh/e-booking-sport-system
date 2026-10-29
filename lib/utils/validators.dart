class Validators {
  static String? email(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) {
      return 'Email is required';
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? password(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) {
      return 'Password is required';
    }
    if (input.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(input)) {
      return 'Password must include at least one uppercase letter';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if ((value ?? '').trim().isEmpty) {
      return 'Please confirm your password';
    }
    if ((value ?? '').trim() != password.trim()) {
      return 'Passwords do not match';
    }
    return null;
  }
}

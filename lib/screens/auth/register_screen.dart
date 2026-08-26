import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/snackbar_helper.dart';
import '../../core/validators/auth_validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/password_field.dart';
import '../../widgets/primary_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    SnackBarHelper.showLoading(
      context,
      title: 'Creating account',
      message: 'Setting up your GMSERP profile…',
    );
    final success = await auth.register(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) {
      SnackBarHelper.hideLoading();
      return;
    }
    SnackBarHelper.hideLoading();

    if (success) {
      SnackBarHelper.showSuccess(context, 'Account successfully created.');
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } else {
      SnackBarHelper.showError(
        context,
        auth.errorMessage ?? 'Something went wrong. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;

    return AuthScaffold(
      showCard: false,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppLogo(size: 96),
            const SizedBox(height: 20),
            Text(
              'Create Account',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Fill in your details to get started',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            CustomTextField(
              controller: _usernameController,
              label: 'Username',
              hint: 'Enter username',
              prefixIcon: Icons.person_outline,
              textInputAction: TextInputAction.next,
              autofocus: true,
              enabled: !isLoading,
              autofillHints: const [AutofillHints.username],
              validator: AuthValidators.username,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'sample@gmail.com',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              enabled: !isLoading,
              autofillHints: const [AutofillHints.email],
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _phoneController,
              label: 'Phone Number',
              hint: '09171234567 or +639171234567',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              enabled: !isLoading,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                LengthLimitingTextInputFormatter(13),
              ],
              validator: AuthValidators.phoneNumber,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Create a strong password',
              textInputAction: TextInputAction.next,
              enabled: !isLoading,
              autofillHints: const [AutofillHints.newPassword],
              validator: AuthValidators.password,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              enabled: !isLoading,
              autofillHints: const [AutofillHints.newPassword],
              validator: (value) => AuthValidators.confirmPassword(
                value,
                _passwordController.text,
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Sign up',
              loadingLabel: 'Creating account...',
              isLoading: isLoading,
              onPressed: _submit,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account?',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        },
                  child: const Text('Login'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

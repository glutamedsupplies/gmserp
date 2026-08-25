import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../core/validators/auth_validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/password_field.dart';
import '../../widgets/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    SnackBarHelper.showLoading(
      context,
      title: 'Signing in',
      message: 'Checking your credentials…',
    );
    final success = await auth.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      rememberMe: true,
    );

    if (!mounted) {
      SnackBarHelper.hideLoading();
      return;
    }
    SnackBarHelper.hideLoading();

    if (success) {
      context.read<CompanyProvider>().clearSelection();
      SnackBarHelper.showSuccess(context, 'Login successful.');
    } else {
      SnackBarHelper.showError(
        context,
        auth.errorMessage ?? 'Invalid email or password.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;

    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppLogo(size: 120),
            const SizedBox(height: 28),
            Text(
              'Welcome',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to continue to GMSERP.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 36),
            CustomTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'Email',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofocus: true,
              enabled: !isLoading,
              autofillHints: const [AutofillHints.email],
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 18),
            PasswordField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Password',
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              enabled: !isLoading,
              autofillHints: const [AutofillHints.password],
              validator: AuthValidators.loginPassword,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        Navigator.of(context)
                            .pushNamed(AppRoutes.forgotPassword);
                      },
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Sign In',
              loadingLabel: 'Signing in...',
              isLoading: isLoading,
              onPressed: _submit,
            ),
            const SizedBox(height: 32),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.of(context).pushNamed(AppRoutes.register);
                        },
                  child: const Text('Sign up'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

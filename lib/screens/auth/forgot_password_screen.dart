import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/snackbar_helper.dart';
import '../../core/validators/auth_validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/primary_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    SnackBarHelper.showLoading(
      context,
      title: 'Sending reset link',
      message: 'Preparing password recovery…',
    );
    final success = await auth.forgotPassword(
      email: _emailController.text.trim(),
    );

    if (!mounted) {
      SnackBarHelper.hideLoading();
      return;
    }
    SnackBarHelper.hideLoading();

    if (success) {
      SnackBarHelper.showSuccess(
        context,
        'Password reset instructions have been sent to your email.',
      );
      Navigator.of(context).pop();
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
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: isLoading
                    ? null
                    : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back to login',
              ),
            ),
            const SizedBox(height: 8),
            const AppLogo(size: 96),
            const SizedBox(height: 20),
            Text(
              'Forgot Password',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your email and we will send you reset instructions.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            CustomTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'sample@gmail.com',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              autofocus: true,
              enabled: !isLoading,
              autofillHints: const [AutofillHints.email],
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'SEND RESET LINK',
              loadingLabel: 'Sending...',
              isLoading: isLoading,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
              child: const Text('Back to Login'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../core/validators/auth_validators.dart';
import '../../providers/auth_provider.dart';
import 'avatar_crop_screen.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/password_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _originalEmail = '';

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _usernameController.text = user?.username ?? '';
    _emailController.text = user?.email ?? '';
    _phoneController.text = user?.phoneNumber ?? '';
    _originalEmail = user?.email ?? '';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final nextEmail = _emailController.text.trim();
    final success = await auth.updateAccount(
      username: _usernameController.text.trim(),
      email: nextEmail,
      phoneNumber: _phoneController.text.trim(),
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text.isEmpty
          ? null
          : _newPasswordController.text,
    );

    if (!mounted) return;

    if (success) {
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      final emailChanged =
          nextEmail.toLowerCase() != _originalEmail.toLowerCase();
      _originalEmail = auth.user?.email ?? nextEmail;
      SnackBarHelper.showSuccess(
        context,
        emailChanged
            ? 'Profile saved. Confirm the new email from your inbox to finish the Gmail change.'
            : 'Profile updated.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        auth.errorMessage ?? 'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (file == null || !mounted) return;

      final original = await file.readAsBytes();
      if (!mounted) return;

      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => AvatarCropScreen(imageBytes: original),
        ),
      );
      if (cropped == null || !mounted) return;

      final auth = context.read<AuthProvider>();
      final success = await auth.saveLocalAvatar(cropped);
      if (!mounted) return;
      if (success) {
        SnackBarHelper.showSuccess(context, 'Profile photo updated.');
      } else {
        SnackBarHelper.showError(
          context,
          auth.errorMessage ?? 'Could not save the profile photo.',
        );
      }
    } on MissingPluginException {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        'Photo picker needs a full app rebuild. Stop the app and run flutter run again.',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        error.message?.isNotEmpty == true
            ? error.message!
            : 'Could not open the photo picker.',
      );
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Could not update profile photo.');
    }
  }

  Future<void> _removePhoto() async {
    final auth = context.read<AuthProvider>();
    final success = await auth.removeLocalAvatar();
    if (!mounted) return;
    if (success) {
      SnackBarHelper.showInfo(context, 'Profile photo removed.');
    } else {
      SnackBarHelper.showError(
        context,
        auth.errorMessage ?? 'Could not remove the profile photo.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoading = auth.isLoading;

    return DashboardScaffold(
      title: 'Account',
      currentRoute: AppRoutes.profile,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Edit profile',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Update your username, Gmail, phone number, or password.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Center(
                  child: GestureDetector(
                    onTap: isLoading ? null : _pickPhoto,
                    child: Stack(
                      children: [
                        UserAvatar(
                          key: ValueKey(auth.avatarRevision),
                          bytes: auth.avatarBytes,
                          name: auth.user?.username ?? auth.user?.email ?? '',
                          size: 96,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap to choose a photo, then crop it. Stored on this device only.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (auth.hasLocalAvatar) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: isLoading ? null : _removePhoto,
                      child: const Text('Remove photo'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                CustomTextField(
                  controller: _usernameController,
                  label: 'Username',
                  hint: 'Your display name',
                  textInputAction: TextInputAction.next,
                  validator: AuthValidators.username,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _emailController,
                  label: 'Gmail',
                  hint: 'you@gmail.com',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: AuthValidators.email,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _phoneController,
                  label: 'Phone number',
                  hint: '09XXXXXXXXX',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: AuthValidators.phoneNumber,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                  ],
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _currentPasswordController,
                  label: 'Current password',
                  hint: 'Required to save changes',
                  textInputAction: TextInputAction.next,
                  validator: AuthValidators.loginPassword,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _newPasswordController,
                  label: 'New password',
                  hint: 'Leave blank to keep current password',
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    return AuthValidators.password(value);
                  },
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _confirmPasswordController,
                  label: 'Confirm new password',
                  hint: 'Repeat new password',
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    if (_newPasswordController.text.isEmpty) return null;
                    return AuthValidators.confirmPassword(
                      value,
                      _newPasswordController.text,
                    );
                  },
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Save changes',
                  isLoading: isLoading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'compact_page.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.autofillHints,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool autofocus;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final AutovalidateMode autovalidateMode;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;

  void _toggleVisibility() {
    setState(() => _obscureText = !_obscureText);
  }

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: density.cardTitleSize,
                fontWeight: FontWeight.w600,
              ),
        ),
        SizedBox(height: density.compact ? 6 : 8),
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          obscureText: _obscureText,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          autofillHints: widget.autofillHints,
          autovalidateMode: widget.autovalidateMode,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: density.bodySize + 1,
              ),
          decoration: InputDecoration(
            hintText: widget.hint ?? widget.label,
            suffixIcon: IconButton(
              onPressed: widget.enabled ? _toggleVisibility : null,
              tooltip: _obscureText ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscureText
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: density.compact ? 18 : 22,
                color: AppColors.of(context).textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

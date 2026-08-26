import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'compact_page.dart';

class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.prefixIcon,
    this.inputFormatters,
    this.autofillHints,
    this.onChanged,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool autofocus;
  final bool enabled;
  final IconData? prefixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final AutovalidateMode autovalidateMode;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: density.cardTitleSize,
                fontWeight: FontWeight.w600,
              ),
        ),
        SizedBox(height: density.compact ? 6 : 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          autofocus: autofocus,
          enabled: enabled,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          onChanged: onChanged,
          autovalidateMode: autovalidateMode,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: density.bodySize + 1,
              ),
          decoration: InputDecoration(
            hintText: hint ?? label,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: density.compact ? 18 : 22)
                : null,
          ),
        ),
      ],
    );
  }
}

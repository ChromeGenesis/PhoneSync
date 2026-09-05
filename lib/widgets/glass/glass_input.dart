import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../shared/text_style_cache.dart';

/// Frosted input decoration helper for text fields.
InputDecoration glassInputDecoration({
  required BuildContext context,
  required String hintText,
  TextStyle? hintStyle,
  Widget? prefixIcon,
  Widget? suffixIcon,
  EdgeInsetsGeometry? contentPadding,
}) {
  final colors = context.colors;

  return InputDecoration(
    hintText: hintText,
    hintStyle:
        hintStyle ??
        OutfitStyle.get(
          color: colors.textSecondary.withAlpha(180),
          fontSize: 12,
        ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: colors.inputBackground,
    contentPadding:
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.inputBorder, width: 1.0),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.inputBorder, width: 1.0),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.goldPrimary, width: 1.5),
    ),
  );
}

/// Reusable glassmorphic labeled input field.
class GlassInput extends StatelessWidget {
  final String? label;
  final TextEditingController? controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;

  const GlassInput({
    super.key,
    this.label,
    this.controller,
    required this.placeholder,
    this.onChanged,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: OutfitStyle.get(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
        ],
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: OutfitStyle.get(
            fontSize: 12.5,
            color: colors.textPrimary,
          ),
          decoration: glassInputDecoration(
            context: context,
            hintText: placeholder,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}

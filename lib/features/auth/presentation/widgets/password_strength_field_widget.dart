import 'package:flutter/material.dart';
import 'package:nexshift_app/core/utils/constants.dart';

class PasswordStrengthField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool showStrengthBar;
  final bool isVisible;
  final VoidCallback onToggle;

  const PasswordStrengthField({
    super.key,
    required this.controller,
    required this.hintText,
    this.showStrengthBar = true,
    required this.isVisible,
    required this.onToggle,
  });

  @override
  State<PasswordStrengthField> createState() => _PasswordStrengthFieldState();
}

class _PasswordStrengthFieldState extends State<PasswordStrengthField> {
  double strength = 0;
  String feedback = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_checkPasswordStrength);
  }

  void _checkPasswordStrength() {
    final password = widget.controller.text;
    double val = 0;

    if (password.isEmpty) {
      val = 0;
      feedback = '';
    } else {
      if (password.length >= 6) val += 0.3;
      if (password.length >= 10) val += 0.2;
      if (RegExp(r'[A-Z]').hasMatch(password)) val += 0.2;
      if (RegExp(r'[0-9]').hasMatch(password)) val += 0.2;
      if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) val += 0.1;

      val = val.clamp(0, 1);

      if (val < 0.4) {
        feedback = 'Faible';
      } else if (val < 0.7) {
        feedback = 'Moyen';
      } else {
        feedback = 'Fort';
      }
    }

    setState(() => strength = val);
  }

  Color _getStrengthColor(ColorScheme colorScheme) {
    if (strength < 0.4) return KColors.weak;
    if (strength < 0.7) return KColors.medium;
    return KColors.strong;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = KTextStyle.descriptionTextStyle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          obscureText: !widget.isVisible,
          style: TextStyle(
            color: colorScheme.tertiary,
            fontSize: textStyle.fontSize,
            fontFamily: textStyle.fontFamily,
            fontWeight: textStyle.fontWeight,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
            suffixIcon: IconButton(
              onPressed: widget.onToggle,
              icon: Icon(
                widget.isVisible ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey,
              ),
            ),
          ),
        ),
        if (widget.showStrengthBar) ...[
          const SizedBox(height: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: _getStrengthColor(colorScheme).withOpacity(0.25),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: strength,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: _getStrengthColor(colorScheme),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            feedback,
            style: TextStyle(
              color: _getStrengthColor(colorScheme),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }
}

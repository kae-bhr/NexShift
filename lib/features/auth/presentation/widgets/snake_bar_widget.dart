import 'package:flutter/material.dart';

class SnakebarWidget {
  static void showSnackBar(
    BuildContext context,
    String message,
    Color backgroundColor,
  ) {
    final textTheme = Theme.of(context).textTheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor.withOpacity(0.9),
        content: Text(
          message,
          style: textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

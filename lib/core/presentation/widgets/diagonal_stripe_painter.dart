import 'package:flutter/material.dart';

/// CustomPainter pour dessiner un motif de hachures diagonales bicolores.
/// Utilisé pour indiquer visuellement les disponibilités (vs astreintes).
class DiagonalStripePainter extends CustomPainter {
  final Color color1;
  final Color color2;

  DiagonalStripePainter({required this.color1, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = color1;
    final paint2 = Paint()..color = color2;
    const stripeWidth = 6.0;

    double x = -size.height;
    bool useColor1 = true;

    while (x < size.width + size.height) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + size.height, size.height)
        ..lineTo(x + size.height + stripeWidth, size.height)
        ..lineTo(x + stripeWidth, 0)
        ..close();

      canvas.drawPath(path, useColor1 ? paint1 : paint2);
      x += stripeWidth;
      useColor1 = !useColor1;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

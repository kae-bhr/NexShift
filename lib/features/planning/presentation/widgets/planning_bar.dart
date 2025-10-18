import 'package:flutter/material.dart';

class PlanningBar extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  // optional callback called when the bar is tapped; provides a DateTime (midpoint)
  final void Function(DateTime at)? onTap;
  final Color? color;
  final bool isSubtle; // if true, use grey background with colored borders
  final bool showLeftBorder; // show colored border on left (real start)
  final bool showRightBorder; // show colored border on right (real end)
  final bool isAvailability; // if true, use diagonal stripe pattern

  const PlanningBar({
    super.key,
    required this.start,
    required this.end,
    this.onTap,
    this.color,
    this.isSubtle = false,
    this.showLeftBorder = true,
    this.showRightBorder = true,
    this.isAvailability = false,
  });

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    // Récupère la largeur totale disponible moins les marges du parent
    final double totalWidth =
        MediaQuery.of(context).size.width - 32; // marge 16px de chaque côté
    final double startHour = start.hour + start.minute / 60;
    double endHour = end.hour + end.minute / 60;

    // Cas particulier : si end est 00:00 du jour suivant, traiter comme 24:00
    if (end.hour == 0 &&
        end.minute == 0 &&
        end.second == 0 &&
        !_isSameDay(start, end)) {
      endHour = 24.0;
    }

    // Position et largeur proportionnelles sur 24h
    final double left =
        (startHour / 24) * totalWidth + 16; // ajoute le décalage marge gauche
    final double width = ((endHour - startHour) / 24) * totalWidth;

    // compute duration for mapping taps to exact time
    final duration = end.difference(start);

    // compute bar width after clamping (used both for layout and for tap mapping)
    final double barWidth = width.clamp(2.0, double.infinity);

    return Positioned(
      left: left,
      top: 0,
      height: 35,
      width: barWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTap != null
            ? (details) {
                // localPosition.dx is relative to the left edge of the bar (0..barWidth)
                double dx = details.localPosition.dx;
                if (dx.isNaN) dx = 0.0;
                dx = dx.clamp(0.0, barWidth);

                final proportion = (barWidth > 0) ? (dx / barWidth) : 0.0;
                final secondsOffset = (duration.inSeconds * proportion).round();
                final at = start.add(Duration(seconds: secondsOffset));
                onTap!(at);
              }
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              // Motif hachuré pour les disponibilités
              if (isAvailability)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DiagonalStripePainter(
                      color1: color!,
                      color2: Colors.white,
                    ),
                  ),
                ),
              // Container avec couleur et bordures
              Container(
                decoration: BoxDecoration(
                  color: isAvailability
                      ? null // Transparent pour montrer le motif
                      : (isSubtle && color != null
                            ? Color.alphaBlend(
                                color!.withValues(alpha: 0.1),
                                Colors.grey.shade200,
                              )
                            : (color ?? Theme.of(context).colorScheme.primary)),
                  border: isSubtle && color != null
                      ? Border(
                          left: showLeftBorder
                              ? BorderSide(color: color!, width: 3)
                              : BorderSide.none,
                          right: showRightBorder
                              ? BorderSide(color: color!, width: 3)
                              : BorderSide.none,
                        )
                      : (isAvailability
                            ? Border.all(color: color!, width: 2)
                            : null),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CustomPainter pour dessiner un motif de hachures diagonales bicolores
class _DiagonalStripePainter extends CustomPainter {
  final Color color1;
  final Color color2;

  _DiagonalStripePainter({required this.color1, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = color1;
    final paint2 = Paint()..color = color2;
    final stripeWidth = 6.0;

    // Dessiner les bandes diagonales alternées
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

import 'package:flutter/material.dart';

class PlanningBar extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  // optional callback called when the bar is tapped; provides a DateTime (midpoint)
  final void Function(DateTime at)? onTap;
  // optional callback for long press start with position
  final void Function(DateTime at, Offset globalPosition)? onLongPressStart;
  // optional callback for drag during long press
  final void Function(DateTime at, Offset globalPosition)? onLongPressMove;
  // optional callback for long press end
  final void Function(DateTime at, Offset globalPosition)? onLongPressEnd;
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
    this.onLongPressStart,
    this.onLongPressMove,
    this.onLongPressEnd,
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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Helper to compute time from local dx
    DateTime timeFromDx(double dx) {
      final clampedDx = dx.isNaN ? 0.0 : dx.clamp(0.0, barWidth);
      final proportion = (barWidth > 0) ? (clampedDx / barWidth) : 0.0;
      final secondsOffset = (duration.inSeconds * proportion).round();
      return start.add(Duration(seconds: secondsOffset));
    }

    return Positioned(
      left: left,
      top: 2,
      height: 34,
      width: barWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onTap != null
            ? (details) => onTap!(timeFromDx(details.localPosition.dx))
            : null,
        onLongPressStart: onLongPressStart != null
            ? (details) => onLongPressStart!(
                  timeFromDx(details.localPosition.dx),
                  details.globalPosition,
                )
            : null,
        onLongPressMoveUpdate: onLongPressMove != null
            ? (details) => onLongPressMove!(
                  timeFromDx(details.localPosition.dx),
                  details.globalPosition,
                )
            : null,
        onLongPressEnd: onLongPressEnd != null
            ? (details) => onLongPressEnd!(
                  timeFromDx(details.localPosition.dx),
                  details.globalPosition,
                )
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              if (isAvailability)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DiagonalStripePainter(
                      color1: color!.withValues(alpha: 0.6),
                      color2: isDark
                          ? Colors.grey.shade800
                          : Colors.white,
                    ),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  color: isAvailability
                      ? null
                      : (isSubtle && color != null
                            ? Color.alphaBlend(
                                color!.withValues(alpha: isDark ? 0.2 : 0.12),
                                isDark
                                    ? Colors.grey.shade900
                                    : Colors.grey.shade100,
                              )
                            : (color ?? Theme.of(context).colorScheme.primary)),
                  border: isSubtle && color != null
                      ? Border(
                          left: showLeftBorder
                              ? BorderSide(color: color!, width: 3.5)
                              : BorderSide.none,
                          right: showRightBorder
                              ? BorderSide(color: color!, width: 3.5)
                              : BorderSide.none,
                        )
                      : (isAvailability
                            ? Border.all(color: color!.withValues(alpha: 0.5), width: 1.5)
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

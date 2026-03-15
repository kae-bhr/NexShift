import 'package:flutter/material.dart';

/// Widget générique qui affiche un menu en overlay positionné juste en dessous
/// du bouton (ou au-dessus si le menu ne tient pas en bas de l'écran).
///
/// Usage :
/// ```dart
/// ContextualMenuButton(
///   menuContent: (close) => MyMenuWidget(onClose: close),
///   child: MyTriggerButton(),
/// )
/// ```
class ContextualMenuButton extends StatefulWidget {
  /// Le bouton déclencheur (n'importe quel widget).
  final Widget child;

  /// Contenu du menu. Reçoit un callback [onClose] à appeler pour fermer le menu.
  final Widget Function(VoidCallback onClose) menuContent;

  /// Rayon des coins du menu (défaut 12).
  final double menuBorderRadius;

  /// Hauteur estimée du menu pour la détection de dépassement (défaut 200).
  final double estimatedMenuHeight;

  const ContextualMenuButton({
    super.key,
    required this.child,
    required this.menuContent,
    this.menuBorderRadius = 12,
    this.estimatedMenuHeight = 200,
  });

  @override
  State<ContextualMenuButton> createState() => _ContextualMenuButtonState();
}

class _ContextualMenuButtonState extends State<ContextualMenuButton>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _animationController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _removeOverlay();
    } else {
      _showMenu();
    }
  }

  void _showMenu() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;

    // Si le menu ne tient pas en bas, on l'affiche au-dessus
    final fitsBelow =
        offset.dy + size.height + 8 + widget.estimatedMenuHeight <= screenHeight;

    _overlayEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: _removeOverlay,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.3)),
            ),
            Positioned(
              left: offset.dx,
              width: size.width,
              top: fitsBelow ? offset.dy + size.height + 8 : null,
              bottom: fitsBelow
                  ? null
                  : screenHeight - offset.dy + 8,
              child: FadeTransition(
                opacity: _animation,
                child: ScaleTransition(
                  scale: _animation,
                  alignment:
                      fitsBelow ? Alignment.topCenter : Alignment.bottomCenter,
                  child: Material(
                    elevation: 8,
                    borderRadius:
                        BorderRadius.circular(widget.menuBorderRadius),
                    child: widget.menuContent(_removeOverlay),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleMenu,
      child: widget.child,
    );
  }
}

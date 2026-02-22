import 'package:flutter/material.dart';

/// Widget générique qui affiche un menu en overlay positionné juste en dessous
/// du bouton (offset = taille bouton + 8px).
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

  const ContextualMenuButton({
    super.key,
    required this.child,
    required this.menuContent,
    this.menuBorderRadius = 12,
  });

  @override
  State<ContextualMenuButton> createState() => _ContextualMenuButtonState();
}

class _ContextualMenuButtonState extends State<ContextualMenuButton>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _animation;
  final LayerLink _layerLink = LayerLink();

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
    final size = renderBox.size;

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
              width: size.width,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0, size.height),
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                child: FadeTransition(
                  opacity: _animation,
                  child: ScaleTransition(
                    scale: _animation,
                    alignment: Alignment.topCenter,
                    child: Material(
                      elevation: 8,
                      borderRadius:
                          BorderRadius.circular(widget.menuBorderRadius),
                      child: widget.menuContent(_removeOverlay),
                    ),
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
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleMenu,
        child: widget.child,
      ),
    );
  }
}

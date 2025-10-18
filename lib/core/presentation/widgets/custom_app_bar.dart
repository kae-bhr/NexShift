import 'package:flutter/material.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// AppBar réutilisable avec design standardisé.
///
/// Reprend le style de TeamPage: fond transparent, elevation 0,
/// titre centré, et une ligne inférieure optionnelle de couleur configurable.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Titre de l'AppBar (String ou Widget personnalisé).
  final dynamic title;

  /// Callback optionnel quand le titre est tapé (pour dropdown, etc.).
  final VoidCallback? onTitleTap;

  /// Couleur de la ligne inférieure (bottom bar). Si null, pas de ligne.
  final Color? bottomColor;

  /// Widget leading optionnel (par défaut: BackButton avec colorScheme.primary).
  final Widget? leading;

  /// Actions optionnelles à droite de l'AppBar.
  final List<Widget>? actions;

  /// Opacité de la ligne inférieure (par défaut 0.7).
  final double bottomOpacity;

  /// Hauteur de la ligne inférieure (par défaut 3).
  final double bottomHeight;

  const CustomAppBar({
    super.key,
    required this.title,
    this.onTitleTap,
    this.bottomColor,
    this.leading,
    this.actions,
    this.bottomOpacity = 0.7,
    this.bottomHeight = 3.0,
  });

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (bottomColor != null ? bottomHeight : 0),
  );

  @override
  Widget build(BuildContext context) {
    Widget titleWidget;

    if (title is String) {
      titleWidget = Text(
        title as String,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontFamily: KTextStyle.regularTextStyle.fontFamily,
          fontWeight: KTextStyle.regularTextStyle.fontWeight,
        ),
      );
    } else {
      titleWidget = title as Widget;
    }

    // Si onTitleTap fourni, envelopper dans un GestureDetector
    if (onTitleTap != null) {
      titleWidget = GestureDetector(
        onTap: onTitleTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            titleWidget,
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      );
    }

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading:
          leading ?? BackButton(color: Theme.of(context).colorScheme.primary),
      centerTitle: true,
      title: titleWidget,
      actions: actions,
      bottom: bottomColor != null
          ? PreferredSize(
              preferredSize: Size.fromHeight(bottomHeight),
              child: Container(
                height: bottomHeight,
                color: bottomColor!.withOpacity(bottomOpacity),
              ),
            )
          : null,
    );
  }
}

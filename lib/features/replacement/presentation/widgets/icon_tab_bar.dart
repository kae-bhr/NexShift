import 'package:flutter/material.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/replacement_sub_tabs.dart';

// Durée totale du cycle de défilement (pause + aller + pause + retour)
const Duration _kMarqueeDuration = Duration(milliseconds: 5000);

/// TabBar personnalisée avec icônes
class IconTabBar extends StatefulWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<SubTabConfig> tabs;
  final Color selectedColor;
  final Color unselectedColor;
  final Map<ReplacementSubTab, int>? badgeCounts;
  final Map<ReplacementSubTab, Color>? badgeColors;
  final Map<ReplacementSubTab, int>? secondaryBadgeCounts;
  final Map<ReplacementSubTab, Color>? secondaryBadgeColors;

  const IconTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    required this.selectedColor,
    required this.unselectedColor,
    this.badgeCounts,
    this.badgeColors,
    this.secondaryBadgeCounts,
    this.secondaryBadgeColors,
  });

  @override
  State<IconTabBar> createState() => _IconTabBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _IconTabBarState extends State<IconTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _marqueeController;

  @override
  void initState() {
    super.initState();
    _marqueeController = AnimationController(
      duration: _kMarqueeDuration,
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _marqueeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade900
          : Colors.grey.shade100,
      child: TabBar(
        controller: widget.controller,
        labelColor: widget.selectedColor,
        unselectedLabelColor: widget.unselectedColor,
        indicatorColor: widget.selectedColor,
        tabs: widget.tabs.map((config) {
          final badgeCount = widget.badgeCounts?[config.type] ?? 0;
          final badgeColor = widget.badgeColors?[config.type];
          final secondaryBadgeCount =
              widget.secondaryBadgeCounts?[config.type] ?? 0;
          final secondaryBadgeColor =
              widget.secondaryBadgeColors?[config.type];

          return Tab(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(config.icon, size: 24),
                // Badge principal (exposant en haut à droite)
                if (badgeCount > 0 && badgeColor != null)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                // Badge secondaire (indice en bas à droite)
                if (secondaryBadgeCount > 0 && secondaryBadgeColor != null)
                  Positioned(
                    right: -8,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: secondaryBadgeColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        secondaryBadgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            child: _AdaptiveTabLabel(
              text: config.label,
              marqueeController: _marqueeController,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// TabBar personnalisée pour les sous-onglets de recherche d'agent (AgentQuery)
class AgentQueryIconTabBar extends StatefulWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<AgentQuerySubTabConfig> tabs;
  final Color selectedColor;
  final Color unselectedColor;
  final Map<AgentQuerySubTab, int>? badgeCounts;
  final Map<AgentQuerySubTab, Color>? badgeColors;

  const AgentQueryIconTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    required this.selectedColor,
    required this.unselectedColor,
    this.badgeCounts,
    this.badgeColors,
  });

  @override
  State<AgentQueryIconTabBar> createState() => _AgentQueryIconTabBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _AgentQueryIconTabBarState extends State<AgentQueryIconTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _marqueeController;

  @override
  void initState() {
    super.initState();
    _marqueeController = AnimationController(
      duration: _kMarqueeDuration,
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _marqueeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade900
          : Colors.grey.shade100,
      child: TabBar(
        controller: widget.controller,
        labelColor: widget.selectedColor,
        unselectedLabelColor: widget.unselectedColor,
        indicatorColor: widget.selectedColor,
        tabs: widget.tabs.map((config) {
          final badgeCount = widget.badgeCounts?[config.type] ?? 0;
          final badgeColor = widget.badgeColors?[config.type];

          return Tab(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(config.icon, size: 24),
                if (badgeCount > 0 && badgeColor != null)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            child: _AdaptiveTabLabel(
              text: config.label,
              marqueeController: _marqueeController,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Label d'onglet adaptatif : texte statique si il tient, sinon défilement
/// synchronisé via le [marqueeController] partagé par la TabBar parente.
class _AdaptiveTabLabel extends StatelessWidget {
  final String text;
  final AnimationController marqueeController;

  const _AdaptiveTabLabel({
    required this.text,
    required this.marqueeController,
  });

  double _measureTextWidth(TextStyle style, TextScaler textScaler) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: double.infinity);
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 80.0;
        final textWidth = _measureTextWidth(inheritedStyle, textScaler);
        // +4px de marge pour éviter que le ClipRect coupe le dernier caractère
        final overflow = textWidth - availableWidth + 4;

        if (overflow <= 0) {
          return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
        }

        // Offset fractionnaire exact pour afficher tout le texte :
        // SlideTransition utilise une fraction de la taille du widget,
        // donc on divise le dépassement en pixels par la largeur du widget.
        final maxOffset = overflow / availableWidth;

        final animation = TweenSequence<Offset>([
          // Pause au début
          TweenSequenceItem(
            tween: ConstantTween(Offset.zero),
            weight: 1,
          ),
          // Défilement vers la gauche jusqu'à la fin du texte
          TweenSequenceItem(
            tween: Tween<Offset>(
              begin: Offset.zero,
              end: Offset(-maxOffset, 0),
            ).chain(CurveTween(curve: Curves.easeInOut)),
            weight: 3,
          ),
          // Pause à la fin
          TweenSequenceItem(
            tween: ConstantTween(Offset(-maxOffset, 0)),
            weight: 1,
          ),
          // Retour
          TweenSequenceItem(
            tween: Tween<Offset>(
              begin: Offset(-maxOffset, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeInOut)),
            weight: 3,
          ),
        ]).animate(marqueeController);

        return SizedBox(
          width: availableWidth,
          child: ClipRect(
            child: SlideTransition(
              position: animation,
              child: Text(
                text,
                overflow: TextOverflow.visible,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        );
      },
    );
  }
}

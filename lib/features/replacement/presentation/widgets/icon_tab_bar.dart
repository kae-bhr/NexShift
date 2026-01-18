import 'package:flutter/material.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/replacement_sub_tabs.dart';

/// TabBar personnalisée avec icônes
class IconTabBar extends StatelessWidget implements PreferredSizeWidget {
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
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade900
          : Colors.grey.shade100,
      child: TabBar(
        controller: controller,
        labelColor: selectedColor,
        unselectedLabelColor: unselectedColor,
        indicatorColor: selectedColor,
        tabs: tabs.map((config) {
          final badgeCount = badgeCounts?[config.type] ?? 0;
          final badgeColor = badgeColors?[config.type];
          final secondaryBadgeCount = secondaryBadgeCounts?[config.type] ?? 0;
          final secondaryBadgeColor = secondaryBadgeColors?[config.type];

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
            child: config.type == ReplacementSubTab.myRequests
                ? _MarqueeText(
                    text: config.label,
                    style: TextStyle(color: selectedColor, fontSize: 14),
                  )
                : Text(config.label),
          );
        }).toList(),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Widget pour afficher du texte avec animation de défilement
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _MarqueeText({required this.text, this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 5000),
      vsync: this,
    );

    // Animation qui va de 0 à 1 puis de 1 à 0 avec des pauses
    _animation = TweenSequence<Offset>([
      // Pause au début
      TweenSequenceItem(
        tween: ConstantTween(const Offset(0.0, 0.0)),
        weight: 1,
      ),
      // Défilement vers la gauche
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: const Offset(0.0, 0.0),
          end: const Offset(-0.4, 0.0),
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 3,
      ),
      // Pause à la fin
      TweenSequenceItem(
        tween: ConstantTween(const Offset(-0.4, 0.0)),
        weight: 1,
      ),
      // Défilement vers la droite (retour)
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: const Offset(-0.4, 0.0),
          end: const Offset(0.0, 0.0),
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 3,
      ),
    ]).animate(_controller);

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100, // Largeur fixe suffisante pour "Mes demandes"
      child: ClipRect(
        child: SlideTransition(
          position: _animation,
          child: Text(
            widget.text,
            style: widget.style,
            overflow: TextOverflow.visible,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}

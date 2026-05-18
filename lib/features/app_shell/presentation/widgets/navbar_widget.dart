import 'package:flutter/material.dart';
import 'package:releve/core/data/datasources/notifiers.dart';
import 'package:releve/core/utils/constants.dart';

class NavbarWidget extends StatelessWidget {
  const NavbarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor =
        isDark ? Colors.white : KColors.appNameColor;
    final inactiveColor =
        isDark ? Colors.white.withValues(alpha: 0.35) : KColors.appNameColor.withValues(alpha: 0.35);

    return ValueListenableBuilder<int>(
      valueListenable: selectedPageNotifier,
      builder: (context, selectedPage, child) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    _NavItem(
                      icon: Icons.shield_moon_rounded,
                      outlineIcon: Icons.shield_moon_outlined,
                      isSelected: selectedPage == 0,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                      onTap: () => selectedPageNotifier.value = 0,
                    ),
                    _NavItem(
                      icon: Icons.calendar_month,
                      outlineIcon: Icons.calendar_month_outlined,
                      isSelected: selectedPage == 1,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                      onTap: () => selectedPageNotifier.value = 1,
                    ),
                  ],
                ),
              ),
              SizedBox(height: bottomInset),
            ],
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData outlineIcon;
  final bool isSelected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.outlineIcon,
    required this.isSelected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              isSelected ? icon : outlineIcon,
              key: ValueKey(isSelected),
              size: 26,
              color: isSelected ? activeColor : inactiveColor,
            ),
          ),
        ),
      ),
    );
  }
}

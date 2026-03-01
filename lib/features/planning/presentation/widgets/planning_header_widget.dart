import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/view_mode.dart';

// Largeur commune des deux colonnes latérales (filtre équipe + toggle Sem./Mois)
const double _kToggleW = 46.0;
// Hauteur du filtre équipe (carré centré, contenu unique)
const double _kFilterH = 74.0;

/// Reusable header used by PlanningPage and HomePage.
///
/// Layout : 3 columns
///   [_TeamFilterButton] | [Personnel/Centre toggle + date nav (Expanded)] | [_ViewModeToggle]
class PlanningHeader extends StatefulWidget {
  final ValueChanged<DateTime>? onWeekChanged;
  final List<Team> availableTeams;

  const PlanningHeader({
    super.key,
    this.onWeekChanged,
    this.availableTeams = const [],
  });

  @override
  State<PlanningHeader> createState() => _PlanningHeaderState();
}

class _PlanningHeaderState extends State<PlanningHeader> {
  @override
  void initState() {
    super.initState();
    viewModeNotifier.addListener(_onNotifierChanged);
    currentMonthNotifier.addListener(_onNotifierChanged);
    currentWeekStartNotifier.addListener(_onNotifierChanged);
  }

  @override
  void dispose() {
    viewModeNotifier.removeListener(_onNotifierChanged);
    currentMonthNotifier.removeListener(_onNotifierChanged);
    currentWeekStartNotifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() => setState(() {});

  static DateTime _getStartOfWeek(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  void _goToPrevious() {
    if (viewModeNotifier.value == ViewMode.week) {
      final newWeekStart = currentWeekStartNotifier.value.subtract(
        const Duration(days: 7),
      );
      currentWeekStartNotifier.value = newWeekStart;
      widget.onWeekChanged?.call(newWeekStart);
    } else {
      final current = currentMonthNotifier.value;
      currentMonthNotifier.value = DateTime(current.year, current.month - 1);
    }
  }

  void _goToNext() {
    if (viewModeNotifier.value == ViewMode.week) {
      final newWeekStart = currentWeekStartNotifier.value.add(
        const Duration(days: 7),
      );
      currentWeekStartNotifier.value = newWeekStart;
      widget.onWeekChanged?.call(newWeekStart);
    } else {
      final current = currentMonthNotifier.value;
      currentMonthNotifier.value = DateTime(current.year, current.month + 1);
    }
  }

  Future<void> _showPicker() async {
    if (viewModeNotifier.value == ViewMode.week) {
      final selectedDate = await showDatePicker(
        context: context,
        initialDate: currentWeekStartNotifier.value,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
        helpText: 'Sélectionner une date',
        cancelText: 'Annuler',
        confirmText: 'Confirmer',
      );
      if (selectedDate != null && mounted) {
        final newWeekStart = _getStartOfWeek(selectedDate);
        currentWeekStartNotifier.value = newWeekStart;
        widget.onWeekChanged?.call(newWeekStart);
      }
    } else {
      final current = currentMonthNotifier.value;
      final selectedDate = await showDatePicker(
        context: context,
        initialDate: DateTime(current.year, current.month, 15),
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
        helpText: 'Sélectionner un mois',
        cancelText: 'Annuler',
        confirmText: 'Confirmer',
      );
      if (selectedDate != null && mounted) {
        currentMonthNotifier.value = DateTime(
          selectedDate.year,
          selectedDate.month,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysOfWeek = List.generate(
      7,
      (i) => currentWeekStartNotifier.value.add(Duration(days: i)),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewMode = viewModeNotifier.value;
    final currentMonth = currentMonthNotifier.value;

    final dateLabel = viewMode == ViewMode.week
        ? "${DateFormat('d MMM', 'fr_FR').format(daysOfWeek.first)} - ${DateFormat('d MMM', 'fr_FR').format(daysOfWeek.last)}"
        : _capitalizeFirst(
            DateFormat('MMMM yyyy', 'fr_FR').format(currentMonth),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Colonne gauche : filtre équipe ──────────────────────
          ValueListenableBuilder<bool>(
            valueListenable: stationViewNotifier,
            builder: (_, stationView, __) => ValueListenableBuilder<String?>(
              valueListenable: selectedTeamNotifier,
              builder: (_, selectedTeam, __) => _TeamFilterButton(
                stationView: stationView,
                availableTeams: widget.availableTeams,
                isDark: isDark,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Colonne centrale : toggle Personnel/Centre + date nav ─
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Toggle Personnel / Centre
                ValueListenableBuilder<bool>(
                  valueListenable: stationViewNotifier,
                  builder: (context, stationView, _) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _SegmentButton(
                                icon: Icons.person_rounded,
                                label: 'Personnel',
                                isSelected: !stationView,
                                onTap: () => stationViewNotifier.value = false,
                              ),
                              _SegmentButton(
                                icon: Icons.fire_truck_rounded,
                                label: 'Centre',
                                isSelected: stationView,
                                onTap: () => stationViewNotifier.value = true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Navigation date
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _NavArrowButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: _goToPrevious,
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _showPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? KColors.appNameColor.withValues(alpha: 0.15)
                              : KColors.appNameColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              viewMode == ViewMode.week
                                  ? Icons.calendar_month_rounded
                                  : Icons.calendar_today_rounded,
                              size: 18,
                              color: KColors.appNameColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dateLabel,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _NavArrowButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: _goToNext,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // ── Colonne droite : toggle Sem./Mois ───────────────────
          // UnconstrainedBox évite que la Row impose sa hauteur au toggle
          UnconstrainedBox(child: _ViewModeToggle()),
        ],
      ),
    );
  }

  String _capitalizeFirst(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTRE ÉQUIPE
// ─────────────────────────────────────────────────────────────────────────────

class _TeamFilterButton extends StatefulWidget {
  final bool stationView;
  final List<Team> availableTeams;
  final bool isDark;

  const _TeamFilterButton({
    required this.stationView,
    required this.availableTeams,
    required this.isDark,
  });

  @override
  State<_TeamFilterButton> createState() => _TeamFilterButtonState();
}

class _TeamFilterButtonState extends State<_TeamFilterButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _openOverlay(BuildContext ctx) {
    if (_overlayEntry != null) {
      _closeOverlay();
      return;
    }

    // Largeur du dropdown
    const dropdownWidth = 200.0;
    // Hauteur approximative du bouton (2 lignes + padding = ~70px)
    const buttonHeight = 70.0;

    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Barrière transparente — ferme au tap extérieur
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeOverlay,
              behavior: HitTestBehavior.opaque,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          // Dropdown positionné sous le bouton, aligné à gauche
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, buttonHeight + 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: _TeamFilterDropdown(
                availableTeams: widget.availableTeams,
                isDark: widget.isDark,
                onClose: _closeOverlay,
                dropdownWidth: dropdownWidth,
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(ctx).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final selectedTeam = selectedTeamNotifier.value;
    final Team? activeTeam = selectedTeam != null
        ? widget.availableTeams.where((t) => t.id == selectedTeam).firstOrNull
        : null;

    // Couleurs selon l'état
    final Color bgColor;
    final Color borderColor;
    final Color contentColor;

    if (!widget.stationView) {
      // Mode Personnel — grisé
      bgColor = widget.isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.grey.shade100;
      borderColor = widget.isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.grey.shade200;
      contentColor = Colors.grey.shade400;
    } else if (activeTeam != null) {
      // Centre + équipe sélectionnée
      bgColor = activeTeam.color.withValues(alpha: widget.isDark ? 0.25 : 0.15);
      borderColor = activeTeam.color.withValues(alpha: 0.4);
      contentColor = activeTeam.color;
    } else {
      // Centre + toutes équipes
      bgColor = KColors.appNameColor.withValues(
        alpha: widget.isDark ? 0.2 : 0.12,
      );
      borderColor = KColors.appNameColor.withValues(alpha: 0.25);
      contentColor = KColors.appNameColor;
    }

    // Contenu centré — icône seule (Toutes/Personnel) ou texte seul (Équipe)
    final Widget innerContent;
    if (widget.stationView && activeTeam != null) {
      innerContent = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          activeTeam.id,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: contentColor,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
      );
    } else {
      innerContent = FittedBox(
        fit: BoxFit.scaleDown,
        child: Icon(Icons.groups_rounded, size: 20, color: contentColor),
      );
    }

    final container = CompositedTransformTarget(
      link: _layerLink,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: _kToggleW,
        height: _kFilterH,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Center(child: innerContent),
      ),
    );

    if (!widget.stationView) {
      return Opacity(opacity: 0.5, child: IgnorePointer(child: container));
    }

    return GestureDetector(
      onTap: () => _openOverlay(context),
      child: container,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DROPDOWN DE SÉLECTION D'ÉQUIPE
// ─────────────────────────────────────────────────────────────────────────────

class _TeamFilterDropdown extends StatelessWidget {
  final List<Team> availableTeams;
  final bool isDark;
  final VoidCallback onClose;
  final double dropdownWidth;

  const _TeamFilterDropdown({
    required this.availableTeams,
    required this.isDark,
    required this.onClose,
    required this.dropdownWidth,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: selectedTeamNotifier,
      builder: (context, selectedTeam, _) {
        return Material(
          color: Colors.transparent,
          child: Container(
            width: dropdownWidth,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Item "Toutes les équipes"
                  _DropdownItem(
                    isDark: isDark,
                    isSelected: selectedTeam == null,
                    onTap: () {
                      selectedTeamNotifier.value = null;
                      onClose();
                    },
                    leading: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: selectedTeam == null
                            ? KColors.appNameColor.withValues(alpha: 0.15)
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.grey.shade100),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.group_rounded,
                        size: 15,
                        color: selectedTeam == null
                            ? KColors.appNameColor
                            : (isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade500),
                      ),
                    ),
                    label: 'Toutes les équipes',
                    labelColor: selectedTeam == null
                        ? KColors.appNameColor
                        : null,
                    checkColor: KColors.appNameColor,
                  ),

                  if (availableTeams.isNotEmpty)
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.grey.shade100,
                    ),

                  // Items équipes
                  ...availableTeams.map((team) {
                    final isSelected = selectedTeam == team.id;
                    return _DropdownItem(
                      isDark: isDark,
                      isSelected: isSelected,
                      onTap: () {
                        selectedTeamNotifier.value = isSelected
                            ? null
                            : team.id;
                        onClose();
                      },
                      leading: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: team.color.withValues(
                            alpha: isSelected ? 0.2 : 0.12,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            team.id,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: team.color,
                            ),
                          ),
                        ),
                      ),
                      label: team.name,
                      labelColor: isSelected ? team.color : null,
                      checkColor: team.color,
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DropdownItem extends StatelessWidget {
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget leading;
  final String label;
  final Color? labelColor;
  final Color checkColor;

  const _DropdownItem({
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    required this.leading,
    required this.label,
    required this.labelColor,
    required this.checkColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: isSelected
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : checkColor.withValues(alpha: 0.06))
              : Colors.transparent,
          child: Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color:
                        labelColor ??
                        (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, size: 16, color: checkColor),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS EXISTANTS (inchangés)
// ─────────────────────────────────────────────────────────────────────────────

/// A single segment in the Personnel/Centre toggle
class _SegmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? KColors.appNameColor.withValues(alpha: 0.3)
                    : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? KColors.appNameColor
                  : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? KColors.appNameColor
                    : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small circular arrow button for navigation
class _NavArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade200,
            ),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Compact Semaine/Mois toggle, reads and writes [viewModeNotifier]
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<ViewMode>(
      valueListenable: viewModeNotifier,
      builder: (context, viewMode, _) {
        return Container(
          width: _kToggleW,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade200,
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ViewModeButton(
                icon: Icons.view_week_rounded,
                label: 'Sem',
                isSelected: viewMode == ViewMode.week,
                onTap: () => viewModeNotifier.value = ViewMode.week,
              ),
              _ViewModeButton(
                icon: Icons.calendar_view_month_rounded,
                label: 'Mois',
                isSelected: viewMode == ViewMode.month,
                onTap: () => viewModeNotifier.value = ViewMode.month,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? KColors.appNameColor.withValues(alpha: 0.3)
                    : KColors.appNameColor.withValues(alpha: 0.12))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? KColors.appNameColor : Colors.grey.shade500,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? KColors.appNameColor : Colors.grey.shade500,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

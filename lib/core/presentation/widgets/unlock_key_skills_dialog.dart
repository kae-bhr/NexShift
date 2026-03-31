import 'package:flutter/material.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Dialog permettant à un utilisateur habilité de débloquer les compétences-clés
/// d'une demande de remplacement en vague 5.
///
/// Affiche les compétences du demandeur en cochant les keySkills par défaut.
/// Retourne la nouvelle liste de keySkills sélectionnées, ou null si annulé.
class UnlockKeySkillsDialog extends StatefulWidget {
  /// Toutes les compétences du demandeur (affichées dans le dialog)
  final List<String> requesterSkills;

  /// Compétences-clés originales (pré-cochées, affichées avec une étoile)
  final List<String> originalKeySkills;

  const UnlockKeySkillsDialog({
    super.key,
    required this.requesterSkills,
    required this.originalKeySkills,
  });

  /// Affiche le dialog et retourne la sélection ou null si annulé
  static Future<List<String>?> show(
    BuildContext context, {
    required List<String> requesterSkills,
    required List<String> originalKeySkills,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (_) => UnlockKeySkillsDialog(
        key: UniqueKey(),
        requesterSkills: requesterSkills,
        originalKeySkills: originalKeySkills,
      ),
    );
  }

  @override
  State<UnlockKeySkillsDialog> createState() => _UnlockKeySkillsDialogState();
}

class _UnlockKeySkillsDialogState extends State<UnlockKeySkillsDialog> {
  late Set<String> _selectedKeySkills;

  @override
  void initState() {
    super.initState();
    _selectedKeySkills = Set.from(widget.originalKeySkills);
  }

  /// Vrai si au moins une keySkill originale a été décochée (relaxation réelle)
  bool get _isUnlockMeaningful =>
      widget.originalKeySkills.any((k) => !_selectedKeySkills.contains(k));

  void _toggle(String skill) {
    setState(() {
      if (_selectedKeySkills.contains(skill)) {
        _selectedKeySkills.remove(skill);
      } else {
        _selectedKeySkills.add(skill);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Colors.deepPurple;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.lock_open_rounded,
              size: 20,
              color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade600,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Débloquer les compétences',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bandeau d'info
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.35 : 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Décochez les compétences ★ à ne plus exiger. '
                        'Les agents sans ces compétences seront ajoutés et notifiés.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.deepPurple[200] : Colors.deepPurple.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Compétences par catégorie
              ..._buildCategoryBlocks(context, isDark),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _isUnlockMeaningful
              ? () => Navigator.of(context).pop(_selectedKeySkills.toList())
              : null,
          icon: const Icon(Icons.lock_open_rounded, size: 16),
          label: const Text('Débloquer'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.deepPurple.shade600,
            foregroundColor: Colors.white,
            disabledBackgroundColor:
                Colors.deepPurple.withValues(alpha: isDark ? 0.2 : 0.15),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCategoryBlocks(BuildContext context, bool isDark) {
    final requesterSet = Set<String>.from(widget.requesterSkills);
    final blocks = <Widget>[];

    for (final category in KSkills.skillCategoryOrder) {
      final categorySkills = (KSkills.skillLevels[category] ?? [])
          .where((s) => s.isNotEmpty && requesterSet.contains(s))
          .toList();

      if (categorySkills.isEmpty) continue;

      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête catégorie
              Row(
                children: [
                  Icon(
                    KSkills.skillCategoryIcons[category] ?? Icons.star_outline,
                    size: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[500],
                  ),
                  const SizedBox(width: 5),
                  Text(
                    category.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Chips
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: categorySkills.map((skill) {
                  final isOriginalKey = widget.originalKeySkills.contains(skill);
                  final isSelected = _selectedKeySkills.contains(skill);
                  final displayName = KSkills.skillShortNames[skill] ?? skill;

                  // Seules les compétences-clés originales sont interactives
                  final isInteractive = isOriginalKey;

                  return _SkillChip(
                    label: displayName,
                    isSelected: isSelected,
                    isKeySkill: isOriginalKey,
                    isInteractive: isInteractive,
                    isDark: isDark,
                    onTap: isInteractive ? () => _toggle(skill) : null,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    return blocks;
  }
}

class _SkillChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isKeySkill;
  final bool isInteractive;
  final bool isDark;
  final VoidCallback? onTap;

  const _SkillChip({
    required this.label,
    required this.isSelected,
    required this.isKeySkill,
    required this.isInteractive,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Compétence-clé sélectionnée : fond violet
    // Compétence-clé désélectionnée : fond rouge pâle (sera débloquée)
    // Compétence normale (non-clé) : fond gris neutre, non interactive
    final Color bgColor;
    final Color borderColor;
    final Color textColor;

    if (!isKeySkill) {
      bgColor = isDark ? Colors.grey.shade800 : Colors.grey.shade100;
      borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
      textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    } else if (isSelected) {
      bgColor = Colors.deepPurple.withValues(alpha: isDark ? 0.25 : 0.1);
      borderColor = Colors.deepPurple.withValues(alpha: isDark ? 0.5 : 0.35);
      textColor = isDark ? Colors.deepPurple.shade200 : Colors.deepPurple.shade700;
    } else {
      // Décochée = sera débloquée
      bgColor = Colors.red.withValues(alpha: isDark ? 0.15 : 0.07);
      borderColor = Colors.red.withValues(alpha: isDark ? 0.4 : 0.25);
      textColor = isDark ? Colors.red.shade300 : Colors.red.shade700;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isKeySkill) ...[
              Icon(
                isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 13,
                color: isSelected
                    ? (isDark ? Colors.amber.shade300 : Colors.amber.shade600)
                    : (isDark ? Colors.red.shade300 : Colors.red.shade400),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isKeySkill ? FontWeight.w600 : FontWeight.w400,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

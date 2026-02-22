import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import '../unified_tile_data.dart';

/// Colonne d'informations pour un agent (gauche ou droite)
/// Affiche : badge statut, nom, dates, station, équipe
class RequestColumn extends StatelessWidget {
  /// Données de l'agent à afficher
  final AgentColumnData data;

  /// Widget du badge de statut
  final Widget statusBadge;

  /// Liste des chefs ayant validé (optionnel, pour l'en-tête)
  final List<ChiefValidationData>? validationChiefs;

  /// Nombre de lignes vides pour alignement (quand l'autre colonne a plus de chefs)
  final int emptyLinesForAlignment;

  /// Afficher la station
  final bool showStation;

  /// Afficher l'équipe
  final bool showTeam;

  /// Afficher les dates (début/fin)
  final bool showDates;

  /// Indique si le badge doit être affiché (true) ou un placeholder (false)
  /// Si null, le badge n'est pas affiché du tout et le divider est masqué
  final bool? showBadge;

  const RequestColumn({
    super.key,
    required this.data,
    required this.statusBadge,
    this.validationChiefs,
    this.emptyLinesForAlignment = 0,
    this.showStation = true,
    this.showTeam = true,
    this.showDates = true,
    this.showBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // En-tête : chefs ayant validé (si présents)
        if (validationChiefs != null && validationChiefs!.isNotEmpty) ...[
          ...validationChiefs!.map(
            (chief) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  if (chief.hasValidated == true)
                    Icon(
                      Icons.check_circle,
                      size: 14,
                      color: Colors.green.shade600,
                    )
                  else if (chief.hasValidated == false)
                    Icon(
                      Icons.cancel,
                      size: 14,
                      color: Colors.red.shade600,
                    )
                  else
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: Colors.orange.shade600,
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      chief.chiefName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Lignes vides pour alignement
        ...List.generate(
          emptyLinesForAlignment,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: SizedBox(height: 18), // Hauteur d'une ligne de chef
          ),
        ),

        // Espacement après les chefs
        if ((validationChiefs != null && validationChiefs!.isNotEmpty) ||
            emptyLinesForAlignment > 0)
          const SizedBox(height: 4),

        // Badge de statut (aligné à droite) ou placeholder pour alignement
        // showBadge == true : afficher le badge
        // showBadge == false : afficher un placeholder de la même hauteur
        // showBadge == null : ne rien afficher (ni badge ni divider)
        if (showBadge != null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: showBadge == true
                ? statusBadge
                : const SizedBox(height: 22), // Hauteur approximative d'un badge compact
          ),

          const SizedBox(height: 8),

          // Divider
          Divider(height: 1, thickness: 1, color: Colors.grey.shade300),

          const SizedBox(height: 8),
        ],

        // Nom de l'agent
        Text(
          data.agentName,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 8),

        // Dates (masquables pour les colonnes droites agentQuery)
        if (showDates) ...[
          _buildInfoRow(
            icon: Icons.calendar_today,
            text: 'Du ${_formatDateTime(data.startTime)}',
            iconColor: Colors.blue.shade600,
          ),
          const SizedBox(height: 4),
          _buildInfoRow(
            icon: Icons.calendar_today,
            text: 'Au ${_formatDateTime(data.endTime)}',
            iconColor: Colors.blue.shade600,
          ),
          const SizedBox(height: 8),
        ],

        // Station
        if (showStation && data.station.isNotEmpty)
          _buildInfoRow(
            icon: Icons.location_on,
            text: data.station,
            iconColor: Colors.grey.shade600,
          ),

        // Équipe
        if (showTeam && data.team != null) ...[
          const SizedBox(height: 4),
          _buildInfoRow(
            icon: Icons.group,
            text: 'Équipe ${data.team}',
            iconColor: Colors.grey.shade600,
          ),
        ],

        // Tags (ex. compétences requises)
        if (data.tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Builder(
            builder: (ctx) => Wrap(
              spacing: 4,
              runSpacing: 4,
              children: data.tags.map((tag) {
                final levelColor = KSkills.skillColors[tag];
                final color = levelColor != null
                    ? KSkills.getColorForSkillLevel(levelColor, ctx)
                    : KColors.appNameColor;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String text,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }
}

/// Colonne placeholder quand aucun remplaçant/proposeur n'est assigné
/// Affiche une colonne vide (invisible) selon les décisions de design
class EmptyColumn extends StatelessWidget {
  /// Nombre de lignes de chefs pour alignement
  final int chiefLinesCount;

  const EmptyColumn({
    super.key,
    this.chiefLinesCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Colonne vide/invisible selon la décision de design
    return const SizedBox.shrink();
  }
}

/// Version compacte de la colonne pour les espaces réduits
class CompactRequestColumn extends StatelessWidget {
  /// Données de l'agent
  final AgentColumnData data;

  /// Badge de statut (optionnel)
  final Widget? statusBadge;

  const CompactRequestColumn({
    super.key,
    required this.data,
    this.statusBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Badge si présent
        if (statusBadge != null) ...[
          statusBadge!,
          const SizedBox(height: 6),
        ],

        // Nom
        Text(
          data.agentName,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 4),

        // Dates sur une ligne
        Text(
          '${_formatDate(data.startTime)} - ${_formatDate(data.endTime)}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd/MM HH:mm').format(dt);
  }
}

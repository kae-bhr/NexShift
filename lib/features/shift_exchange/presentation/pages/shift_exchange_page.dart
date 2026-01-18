import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Page de création d'une demande d'échange d'astreinte
/// Similaire à replacement_page.dart mais pour les échanges
class ShiftExchangePage extends StatefulWidget {
  final Planning planning;
  final User currentUser;

  const ShiftExchangePage({
    super.key,
    required this.planning,
    required this.currentUser,
  });

  @override
  State<ShiftExchangePage> createState() => _ShiftExchangePageState();
}

class _ShiftExchangePageState extends State<ShiftExchangePage> {
  final _exchangeService = ShiftExchangeService();
  bool _isSubmitting = false;

  /// Formate une date au format DD/MM/YYYY HH:mm
  String _formatDateTime(DateTime dt) {
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  /// Détermine la couleur du texte en fonction de la luminance du fond
  Color _adaptiveTextColor(BuildContext context, {Color? backgroundColor}) {
    final bg = backgroundColor ?? Theme.of(context).cardColor;
    final luminance = bg.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  /// Propose l'échange d'astreinte
  Future<void> _proposeExchange() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Afficher le snackbar "Envoi des notifications..."
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Envoi des notifications...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Petit délai pour que le snackbar s'affiche
      await Future.delayed(const Duration(milliseconds: 500));

      // Créer la demande d'échange
      await _exchangeService.createExchangeRequest(
        initiatorId: widget.currentUser.id,
        planningId: widget.planning.id,
        station: widget.planning.station,
      );

      if (mounted) {
        // Afficher le snackbar de succès
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications envoyées ✅'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Retourner à la page précédente après un court délai
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Toujours afficher l'astreinte complète (vert car pas de période non couverte)
    final cardColor = Colors.green[50];
    final textColor = _adaptiveTextColor(context, backgroundColor: cardColor);

    return Scaffold(
      appBar: CustomAppBar(
        title: "Échange d'astreinte",
        bottomColor: KColors.appNameColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Encart avec les détails de l'astreinte (non modifiable)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.green[200]!, width: 2),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event, color: Colors.green[700], size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Astreinte à échanger',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(color: Colors.green[200]),
                    const SizedBox(height: 12),
                    // Équipe
                    Row(
                      children: [
                        Icon(
                          Icons.group,
                          size: 20,
                          color: textColor.withOpacity(0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Équipe ${widget.planning.team}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Date de début
                    Row(
                      children: [
                        Icon(
                          Icons.event_available,
                          size: 20,
                          color: textColor.withOpacity(0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Début: ${_formatDateTime(widget.planning.startTime)}',
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Date de fin
                    Row(
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 20,
                          color: textColor.withOpacity(0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Fin: ${_formatDateTime(widget.planning.endTime)}',
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Info : durée totale
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[300]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: Colors.green[800],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Toute la durée de l\'astreinte sera proposée à l\'échange',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Bouton "Proposer un échange"
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _proposeExchange,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.swap_horiz),
              label: Text(
                _isSubmitting ? 'Envoi en cours...' : 'Proposer un échange',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: KColors.appNameColor,
              ),
            ),

            const SizedBox(height: 24),

            // Card explicative
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue[700], size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Comment ça marche ?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoStep(
                      '1',
                      'Votre demande sera visible par tous les agents possédant vos compétences-clés',
                      Colors.blue[700]!,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoStep(
                      '2',
                      'Les agents intéressés pourront proposer une ou plusieurs de leurs astreintes en échange',
                      Colors.blue[700]!,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoStep(
                      '3',
                      'Vous sélectionnerez la proposition qui vous convient le mieux',
                      Colors.blue[700]!,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoStep(
                      '4',
                      'Les chefs des deux équipes devront valider l\'échange',
                      Colors.blue[700]!,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoStep(String number, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.blue[900]),
          ),
        ),
      ],
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/app_empty_state.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/replacement_sub_tabs.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

/// Type de demande de remplacement
enum ReplacementItemType {
  automatic, // Demande automatique (ReplacementRequest)
  manual,    // Proposition manuelle (ManualReplacementProposal)
}

/// Classe pour représenter une proposition de remplacement manuel
class ManualReplacementProposal {
  final String id;
  final String proposerId;
  final String proposerName;
  final String replacedId;
  final String replacedName;
  final String? replacedTeam;
  final String replacerId;
  final String replacerName;
  final String? replacerTeam;
  final String planningId;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final DateTime? createdAt;

  ManualReplacementProposal({
    required this.id,
    required this.proposerId,
    required this.proposerName,
    required this.replacedId,
    required this.replacedName,
    this.replacedTeam,
    required this.replacerId,
    required this.replacerName,
    this.replacerTeam,
    required this.planningId,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.createdAt,
  });

  factory ManualReplacementProposal.fromJson(Map<String, dynamic> json) {
    try {
      return ManualReplacementProposal(
        id: json['id'] as String? ?? '',
        proposerId: json['proposerId'] as String? ?? '',
        proposerName: json['proposerName'] as String? ?? '',
        replacedId: json['replacedId'] as String? ?? '',
        replacedName: json['replacedName'] as String? ?? '',
        replacedTeam: json['replacedTeam'] as String?,
        replacerId: json['replacerId'] as String? ?? '',
        replacerName: json['replacerName'] as String? ?? '',
        replacerTeam: json['replacerTeam'] as String?,
        planningId: json['planningId'] as String? ?? '',
        startTime: json['startTime'] is Timestamp
            ? (json['startTime'] as Timestamp).toDate()
            : DateTime.now(),
        endTime: json['endTime'] is Timestamp
            ? (json['endTime'] as Timestamp).toDate()
            : DateTime.now(),
        status: json['status'] as String? ?? 'pending',
        createdAt: json['createdAt'] is Timestamp
            ? (json['createdAt'] as Timestamp).toDate()
            : null,
      );
    } catch (e) {
      debugPrint('Error parsing ManualReplacementProposal: $e');
      rethrow;
    }
  }
}

/// Wrapper unifié pour afficher les demandes automatiques et manuelles ensemble
class UnifiedReplacementItem {
  final ReplacementItemType type;
  final ReplacementRequest? automaticRequest;
  final ManualReplacementProposal? manualProposal;

  UnifiedReplacementItem.automatic(ReplacementRequest request)
      : type = ReplacementItemType.automatic,
        automaticRequest = request,
        manualProposal = null;

  UnifiedReplacementItem.manual(ManualReplacementProposal proposal)
      : type = ReplacementItemType.manual,
        automaticRequest = null,
        manualProposal = proposal;

  /// Date de début (pour le tri)
  DateTime get startTime {
    if (type == ReplacementItemType.automatic) {
      return automaticRequest!.startTime;
    } else {
      return manualProposal!.startTime;
    }
  }

  /// Statut unifié
  String get status {
    if (type == ReplacementItemType.automatic) {
      return automaticRequest!.status.toString().split('.').last;
    } else {
      return manualProposal!.status;
    }
  }

  /// ID du demandeur/proposeur
  String get requesterId {
    if (type == ReplacementItemType.automatic) {
      return automaticRequest!.requesterId;
    } else {
      // Pour les manuelles, le "demandeur" est celui qui est remplacé
      return manualProposal!.replacedId;
    }
  }
}

/// Widget pour afficher les demandes de remplacement filtrées selon le sous-onglet
class FilteredRequestsView extends StatefulWidget {
  final ReplacementSubTab subTab;
  final String? currentUserId;
  final String? currentStationId;
  final User? currentUser;
  final DateTime? selectedMonth; // Uniquement pour l'historique
  final Widget Function(ReplacementRequest request, ReplacementSubTab subTab) buildCard;
  final Widget Function(ManualReplacementProposal proposal, ReplacementSubTab subTab)? buildManualCard;

  const FilteredRequestsView({
    super.key,
    required this.subTab,
    required this.currentUserId,
    required this.currentStationId,
    required this.currentUser,
    required this.buildCard,
    this.buildManualCard,
    this.selectedMonth,
  });

  @override
  State<FilteredRequestsView> createState() => _FilteredRequestsViewState();
}

class _FilteredRequestsViewState extends State<FilteredRequestsView> {
  final _notificationService = ReplacementNotificationService();

  String _getAutomaticRequestsPath() {
    return EnvironmentConfig.getCollectionPath(
        'replacements/automatic/replacementRequests', widget.currentStationId);
  }

  String _getManualProposalsPath() {
    return EnvironmentConfig.getCollectionPath(
        'replacements/manual/proposals', widget.currentStationId);
  }

  /// Stream combiné des demandes automatiques et manuelles
  Stream<List<UnifiedReplacementItem>> _getCombinedStream() {
    final automaticPath = _getAutomaticRequestsPath();
    final manualPath = _getManualProposalsPath();

    debugPrint('[DEBUG FilteredRequests] Automatic path: $automaticPath');
    debugPrint('[DEBUG FilteredRequests] Manual path: $manualPath');

    final automaticStream = _notificationService.firestore
        .collection(automaticPath)
        .snapshots()
        .map((snapshot) {
          debugPrint('[DEBUG FilteredRequests] Automatic requests: ${snapshot.docs.length}');
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return UnifiedReplacementItem.automatic(ReplacementRequest.fromJson(data));
          }).toList();
        });

    final manualStream = _notificationService.firestore
        .collection(manualPath)
        .snapshots()
        .map((snapshot) {
          debugPrint('[DEBUG FilteredRequests] Manual proposals: ${snapshot.docs.length}');
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return UnifiedReplacementItem.manual(ManualReplacementProposal.fromJson(data));
          }).toList();
        });

    // Combiner les deux streams
    return automaticStream.asyncExpand((automaticItems) {
      return manualStream.map((manualItems) {
        final combined = [...automaticItems, ...manualItems];
        debugPrint('[DEBUG FilteredRequests] Combined items: ${combined.length}');
        return combined;
      });
    });
  }

  /// Vérifie si la date de début est aujourd'hui ou dans le futur
  bool _isFutureOrToday(DateTime startTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = DateTime(startTime.year, startTime.month, startTime.day);
    return startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
  }

  List<UnifiedReplacementItem> _filterItems(List<UnifiedReplacementItem> items) {
    switch (widget.subTab) {
      case ReplacementSubTab.pending:
        // Demandes en attente :
        // - status == pending
        // - pas ses propres demandes
        // - pas déjà refusé
        // - pas déjà en attente de validation
        // - date de début >= aujourd'hui
        return items.where((item) {
          if (item.status != 'pending') return false;
          if (!_isFutureOrToday(item.startTime)) return false;

          if (item.type == ReplacementItemType.automatic) {
            final r = item.automaticRequest!;
            // Exclure mes propres demandes
            if (r.requesterId == widget.currentUserId) return false;
            // Exclure si j'ai déjà refusé
            if (r.declinedByUserIds.contains(widget.currentUserId)) return false;
            // Exclure si je suis déjà en attente de validation (j'ai accepté)
            if (r.pendingValidationUserIds.contains(widget.currentUserId)) return false;
            return true;
          } else {
            // Pour les manuelles, afficher si on est le remplaçant désigné
            return item.manualProposal!.replacerId == widget.currentUserId;
          }
        }).toList();

      case ReplacementSubTab.myRequests:
        // Mes demandes :
        // - requesterId == currentUserId (ou replacedId pour manuel)
        // - status != cancelled/accepted
        // - date de début >= aujourd'hui
        return items.where((item) {
          if (item.status == 'accepted' || item.status == 'cancelled') return false;
          if (!_isFutureOrToday(item.startTime)) return false;

          if (item.type == ReplacementItemType.automatic) {
            return item.automaticRequest!.requesterId == widget.currentUserId;
          } else {
            // Pour les manuelles, c'est "ma demande" si je suis le remplacé (celui qui demande à être remplacé)
            return item.manualProposal!.replacedId == widget.currentUserId;
          }
        }).toList();

      case ReplacementSubTab.toValidate:
        // Demandes à valider :
        // UNIQUEMENT pour les demandes automatiques avec acceptations en attente de validation chef
        // Les demandes manuelles apparaissent dans "En attente" (pas de validation chef requise)
        return items.where((item) {
          // Exclure les demandes manuelles - elles sont dans "En attente"
          if (item.type == ReplacementItemType.manual) return false;

          if (item.status != 'pending') return false;
          if (!_isFutureOrToday(item.startTime)) return false;

          final r = item.automaticRequest!;
          if (r.pendingValidationUserIds.isEmpty) return false;

          // Visibilité : initiateur OU remplaçant en attente OU chef de l'équipe
          final isInitiator = r.requesterId == widget.currentUserId;
          final isPendingValidator = r.pendingValidationUserIds.contains(widget.currentUserId);
          final isChiefOfTeam = widget.currentUser != null &&
              (widget.currentUser!.status == 'chief' || widget.currentUser!.status == 'leader') &&
              r.team == widget.currentUser!.team;

          return isInitiator || isPendingValidator || isChiefOfTeam;
        }).toList();

      case ReplacementSubTab.history:
        // Historique : status == accepted
        final historicItems = items.where((item) =>
          item.status == 'accepted'
        ).toList();

        // Si un mois est sélectionné, filtrer par mois
        if (widget.selectedMonth != null) {
          final startOfMonth = DateTime(
            widget.selectedMonth!.year,
            widget.selectedMonth!.month,
            1,
          );
          final endOfMonth = DateTime(
            widget.selectedMonth!.year,
            widget.selectedMonth!.month + 1,
            1,
          );

          return historicItems.where((item) =>
            item.startTime.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
            item.startTime.isBefore(endOfMonth)
          ).toList();
        }

        return historicItems;
    }
  }

  Future<bool> _canViewAutomaticRequest(ReplacementRequest request) async {
    if (widget.currentUserId == null) return false;

    try {
      // Phase 3 : TOUS les agents de la même station peuvent voir la demande
      if (request.station == widget.currentStationId) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking view permission: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentUserId == null || widget.currentStationId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    debugPrint('[DEBUG FilteredRequests] CurrentUserId: ${widget.currentUserId}');
    debugPrint('[DEBUG FilteredRequests] CurrentStationId: ${widget.currentStationId}');

    return StreamBuilder<List<UnifiedReplacementItem>>(
      stream: _getCombinedStream().asyncMap((allItems) async {
        debugPrint('[DEBUG FilteredRequests] Total items: ${allItems.length}');

        // Appliquer les règles de visibilité
        final visibleItems = <UnifiedReplacementItem>[];
        for (final item in allItems) {
          if (item.type == ReplacementItemType.automatic) {
            // Les demandes acceptées sont visibles par tous
            if (item.automaticRequest!.status == ReplacementRequestStatus.accepted) {
              visibleItems.add(item);
              continue;
            }
            // Pour les autres, vérifier la visibilité
            final canView = await _canViewAutomaticRequest(item.automaticRequest!);
            if (canView) {
              visibleItems.add(item);
            }
          } else {
            // Pour les manuelles, visible si on est concerné (remplacé ou remplaçant)
            final proposal = item.manualProposal!;
            if (proposal.replacedId == widget.currentUserId ||
                proposal.replacerId == widget.currentUserId ||
                proposal.proposerId == widget.currentUserId) {
              visibleItems.add(item);
            }
          }
        }

        debugPrint('[DEBUG FilteredRequests] Visible items: ${visibleItems.length}');

        // Filtrer selon le sous-onglet
        final filteredItems = _filterItems(visibleItems);

        debugPrint('[DEBUG FilteredRequests] After filter (${widget.subTab}): ${filteredItems.length}');

        // Trier par date
        filteredItems.sort((a, b) => a.startTime.compareTo(b.startTime));

        return filteredItems;
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {}); // Force rebuild to restart stream
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Erreur: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {}); // Force rebuild to restart stream
            },
            child: _buildEmptyState(),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {}); // Force rebuild to restart stream
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item.type == ReplacementItemType.automatic) {
                return widget.buildCard(item.automaticRequest!, widget.subTab);
              } else {
                // Utiliser le builder manuel si fourni, sinon créer une carte par défaut
                if (widget.buildManualCard != null) {
                  return widget.buildManualCard!(item.manualProposal!, widget.subTab);
                } else {
                  return _buildDefaultManualCard(item.manualProposal!);
                }
              }
            },
          ),
        );
      },
    );
  }

  /// Carte par défaut pour les propositions manuelles (si aucun builder fourni)
  Widget _buildDefaultManualCard(ManualReplacementProposal proposal) {
    final isReplacer = proposal.replacerId == widget.currentUserId;
    final isReplaced = proposal.replacedId == widget.currentUserId;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (proposal.status) {
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusText = isReplacer ? 'En attente de votre réponse' : 'En attente';
        break;
      case 'accepted':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Accepté';
        break;
      case 'declined':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Refusé';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
        statusText = proposal.status;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge "Manuel"
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_pin, size: 14, color: Colors.purple.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Manuel',
                        style: TextStyle(
                          color: Colors.purple.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Détails
            Text(
              isReplaced
                  ? 'Vous avez demandé à ${proposal.replacerName} de vous remplacer'
                  : 'Demande de ${proposal.replacedName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Du ${_formatDateTime(proposal.startTime)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        'Au ${_formatDateTime(proposal.endTime)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildEmptyState() {
    switch (widget.subTab) {
      case ReplacementSubTab.pending:
        return AppEmptyState(
          icon: Icons.inbox_outlined,
          headline: 'Aucune demande disponible',
          subtitle: 'Il n\'y a pas de demandes de remplacement compatibles',
        );
      case ReplacementSubTab.myRequests:
        return AppEmptyState(
          icon: Icons.person_search_rounded,
          headline: 'Aucune demande en cours',
          subtitle: 'Vous n\'avez pas de demandes de remplacement en cours',
        );
      case ReplacementSubTab.toValidate:
        return AppEmptyState(
          icon: Icons.check_circle_outline,
          headline: 'Aucune validation requise',
          subtitle: 'Il n\'y a pas de demandes à valider',
        );
      case ReplacementSubTab.history:
        return AppEmptyState(
          icon: Icons.history,
          headline: 'Aucun historique',
          subtitle: 'Il n\'y a pas d\'entrées pour cette période',
        );
    }
  }
}

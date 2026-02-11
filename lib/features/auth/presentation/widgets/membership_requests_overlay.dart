import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/membership_request_model.dart';
import 'package:nexshift_app/core/services/cloud_functions_service.dart';

/// Overlay flottant affichant les demandes d'adhésion en attente
/// Visible uniquement pour les administrateurs et chefs d'équipe
class MembershipRequestsOverlay extends StatefulWidget {
  final String stationId;

  const MembershipRequestsOverlay({
    super.key,
    required this.stationId,
  });

  @override
  State<MembershipRequestsOverlay> createState() =>
      _MembershipRequestsOverlayState();
}

class _MembershipRequestsOverlayState extends State<MembershipRequestsOverlay> {
  final _cloudFunctionsService = CloudFunctionsService();

  int _pendingCount = 0;
  bool _isExpanded = false;
  bool _isLoading = false;
  List<MembershipRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    try {
      final count = await _cloudFunctionsService.getPendingMembershipRequestsCount(
        stationId: widget.stationId,
      );

      if (mounted) {
        setState(() {
          _pendingCount = count;
        });
      }
    } catch (e) {
      debugPrint('Error loading pending count: $e');
    }
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final requests = await _cloudFunctionsService.getMembershipRequests(
        stationId: widget.stationId,
      );

      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleRequest(MembershipRequest request, bool accept) async {
    // Afficher dialog de confirmation/configuration
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _HandleRequestDialog(
        request: request,
        accept: accept,
      ),
    );

    if (result == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _cloudFunctionsService.handleMembershipRequest(
        stationId: widget.stationId,
        requestAuthUid: request.authUid,
        accept: accept,
        role: result['role'] as String?,
        team: result['team'] as String?,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Demande acceptée pour ${request.firstName} ${request.lastName}'
                : 'Demande refusée',
          ),
          backgroundColor: accept ? Colors.green : Colors.orange,
        ),
      );

      // Recharger les demandes et le compteur
      await _loadRequests();
      await _loadPendingCount();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ne pas afficher si aucune demande en attente
    if (_pendingCount == 0 && !_isExpanded) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: 16,
      bottom: 80,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _isExpanded ? 320 : 60,
          height: _isExpanded ? 400 : 60,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: _isExpanded ? _buildExpandedView() : _buildCollapsedView(),
        ),
      ),
    );
  }

  Widget _buildCollapsedView() {
    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = true;
        });
        _loadRequests();
      },
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          const Center(
            child: Icon(
              Icons.people_alt,
              color: Colors.white,
              size: 30,
            ),
          ),
          if (_pendingCount > 0)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                child: Text(
                  '$_pendingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandedView() {
    return Column(
      children: [
        // En-tête
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.people_alt, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Demandes d\'adhésion',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _isExpanded = false;
                  });
                },
              ),
            ],
          ),
        ),

        // Liste des demandes
        Expanded(
          child: Container(
            color: Colors.white,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _requests.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucune demande en attente',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) {
                          final request = _requests[index];
                          return _RequestCard(
                            request: request,
                            onAccept: () => _handleRequest(request, true),
                            onReject: () => _handleRequest(request, false),
                            isLoading: _isLoading,
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final MembershipRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool isLoading;

  const _RequestCard({
    required this.request,
    required this.onAccept,
    required this.onReject,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.firstName} ${request.lastName}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Matricule: ${request.matricule}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: isLoading ? null : onReject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Refuser'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: isLoading ? null : onAccept,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Accepter'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HandleRequestDialog extends StatefulWidget {
  final MembershipRequest request;
  final bool accept;

  const _HandleRequestDialog({
    required this.request,
    required this.accept,
  });

  @override
  State<_HandleRequestDialog> createState() => _HandleRequestDialogState();
}

class _HandleRequestDialogState extends State<_HandleRequestDialog> {
  String _selectedRole = 'agent';
  final _teamController = TextEditingController();

  @override
  void dispose() {
    _teamController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.accept) {
      // Confirmation de refus simple
      return AlertDialog(
        title: const Text('Refuser la demande'),
        content: Text(
          'Êtes-vous sûr de vouloir refuser la demande de ${widget.request.firstName} ${widget.request.lastName} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {}),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Refuser'),
          ),
        ],
      );
    }

    // Configuration pour acceptation
    return AlertDialog(
      title: const Text('Accepter la demande'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.request.firstName} ${widget.request.lastName}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Rôle:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'agent', child: Text('Agent')),
                DropdownMenuItem(value: 'leader', child: Text('Chef d\'équipe')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedRole = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            const Text('Équipe (optionnel):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _teamController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ex: Équipe A',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'role': _selectedRole,
              'team': _teamController.text.trim().isEmpty
                  ? null
                  : _teamController.text.trim(),
            });
          },
          child: const Text('Accepter'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';

/// Teams tab page - manages station teams
class TeamsTabPage extends StatefulWidget {
  final List<User> allUsers;
  final List<Team> allTeams;
  final Map<String, List<User>> usersByTeam;
  final User? currentUser;
  final VoidCallback onDataChanged;

  const TeamsTabPage({
    super.key,
    required this.allUsers,
    required this.allTeams,
    required this.usersByTeam,
    required this.currentUser,
    required this.onDataChanged,
  });

  @override
  State<TeamsTabPage> createState() => _TeamsTabPageState();
}

class _TeamsTabPageState extends State<TeamsTabPage> {
  bool get _isLeader =>
      widget.currentUser?.status == 'leader' ||
      widget.currentUser?.admin == true;

  @override
  Widget build(BuildContext context) {
    final totalAgents = widget.allUsers.length;
    final totalTeams = widget.allTeams.length;

    // Trier les équipes par ordre
    final sortedTeams = List<Team>.from(widget.allTeams)
      ..sort((a, b) => a.order.compareTo(b.order));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Statistics Header
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    Theme.of(context).colorScheme.primary.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(
                    icon: Icons.groups,
                    value: '$totalTeams',
                    label: 'Équipe${totalTeams > 1 ? 's' : ''}',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  Container(width: 1, height: 40, color: Colors.grey.shade300),
                  _buildStatColumn(
                    icon: Icons.people,
                    value: '$totalAgents',
                    label: 'Agent${totalAgents > 1 ? 's' : ''}',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),

          // Teams Grid
          if (sortedTeams.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.group_off,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aucune équipe',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Appuyez sur + pour créer une équipe',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: _isLeader
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sortedTeams.length,
                        onReorder: (oldIndex, newIndex) {
                          _reorderTeams(oldIndex, newIndex, sortedTeams);
                        },
                        itemBuilder: (context, index) {
                          final team = sortedTeams[index];
                          return _buildTeamListCard(
                            team,
                            index,
                            key: ValueKey(team.id),
                          );
                        },
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sortedTeams.length,
                        itemBuilder: (context, index) {
                          final team = sortedTeams[index];
                          return _buildTeamListCard(team, index);
                        },
                      ),
                    ),
            ),

          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: _isLeader
          ? FloatingActionButton.extended(
              onPressed: _showAddTeamDialog,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle équipe'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
    );
  }

  Widget _buildStatColumn({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  void _reorderTeams(int oldIndex, int newIndex, List<Team> sortedTeams) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final team = sortedTeams.removeAt(oldIndex);
    sortedTeams.insert(newIndex, team);

    // Mettre à jour l'ordre de toutes les équipes
    final teamRepo = TeamRepository();
    for (int i = 0; i < sortedTeams.length; i++) {
      final updatedTeam = sortedTeams[i].copyWith(order: i);
      await teamRepo.upsert(updatedTeam);
    }

    // Notifier le changement
    teamDataChangedNotifier.value++;
    widget.onDataChanged();
  }

  Widget _buildTeamListCard(Team team, int index, {Key? key}) {
    final teamUsers = widget.usersByTeam[team.id] ?? [];
    final textColor = _getTextColorForBackground(team.color);

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: team.color.withOpacity(0.3), width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              team.color.withOpacity(0.15),
              team.color.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLeader)
                Icon(Icons.drag_handle, color: team.color.withOpacity(0.5)),
              const SizedBox(width: 8),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: team.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: team.color.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    team.id,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          title: Text(
            team.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: team.color,
            ),
          ),
          subtitle: Text(
            '${teamUsers.length} membre${teamUsers.length > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          trailing: _isLeader
              ? PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: team.color),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit_name',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 18),
                          SizedBox(width: 8),
                          Text('Modifier le nom'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit_color',
                      child: Row(
                        children: [
                          Icon(Icons.palette, size: 18),
                          SizedBox(width: 8),
                          Text('Modifier la couleur'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete,
                            size: 18,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Supprimer',
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) => _handleTeamAction(value, team),
                )
              : null,
        ),
      ),
    );
  }

  Color _getTextColorForBackground(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  void _handleTeamAction(String action, Team team) {
    switch (action) {
      case 'edit_name':
        _showEditTeamNameDialog(team);
        break;
      case 'edit_color':
        _showEditTeamColorDialog(team);
        break;
      case 'delete':
        _showDeleteTeamDialog(team);
        break;
    }
  }

  Future<void> _showAddTeamDialog() async {
    // Vérifier que l'utilisateur courant existe
    if (widget.currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur: utilisateur non connecté'),
        ),
      );
      return;
    }

    // Generate new team ID based on existing teams
    final existingIds = widget.allTeams.map((t) => t.id).toList();
    String newId = 'A';
    final alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    for (var char in alphabet.split('')) {
      if (!existingIds.contains(char)) {
        newId = char;
        break;
      }
    }

    // If all single letters are taken, use double letters
    if (existingIds.contains(newId)) {
      for (var i = 0; i < alphabet.length; i++) {
        for (var j = 0; j < alphabet.length; j++) {
          final id = alphabet[i] + alphabet[j];
          if (!existingIds.contains(id)) {
            newId = id;
            break;
          }
        }
        if (!existingIds.contains(newId)) break;
      }
    }

    // Create new team with default values
    final newTeam = Team(
      id: newId,
      name: 'Nouvelle équipe',
      stationId: widget.currentUser!.station,
      color: Colors.grey.shade400,
    );

    // Save to repository
    final teamRepo = TeamRepository();
    await teamRepo.upsert(newTeam);

    // Notify other parts of the app to reload team data
    teamDataChangedNotifier.value++;
    widget.onDataChanged();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Équipe ${newTeam.id} créée. Utilisez le menu pour la personnaliser.',
        ),
      ),
    );
  }

  void _showEditTeamNameDialog(Team team) {
    final nameController = TextEditingController(text: team.name);
    final idController = TextEditingController(text: team.id);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier l\'équipe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nom de l\'équipe',
                hintText: 'Ex: Équipe 1',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'Initiale de l\'équipe',
                hintText: 'Ex: A, B, 1, 2...',
                helperText: 'L\'initiale apparaît dans les badges et titres',
              ),
              maxLength: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              final newId = idController.text.trim();

              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Le nom ne peut pas être vide')),
                );
                return;
              }

              if (newId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('L\'initiale ne peut pas être vide')),
                );
                return;
              }

              // Check if new ID already exists (excluding current team)
              final existingTeam = widget.allTeams.firstWhere(
                (t) => t.id == newId && t.id != team.id,
                orElse: () => Team(id: '', name: '', stationId: '', color: Colors.grey),
              );

              if (existingTeam.id.isNotEmpty) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('L\'initiale "$newId" est déjà utilisée')),
                );
                return;
              }

              final teamRepo = TeamRepository();

              // If ID changed, we need to delete old team and create new one
              if (newId != team.id) {
                // Delete old team (pass stationId for dev mode)
                await teamRepo.delete(team.id, stationId: team.stationId);

                // Create new team with new ID
                final newTeam = Team(
                  id: newId,
                  name: newName,
                  stationId: team.stationId,
                  color: team.color,
                );
                await teamRepo.upsert(newTeam);

                // Update all users with the old team to the new team
                final LocalRepository localRepo = LocalRepository();
                final allUsers = await localRepo.getAllUsers();
                final usersToUpdate = allUsers.where((u) => u.team == team.id).toList();

                for (final user in usersToUpdate) {
                  final updatedUser = user.copyWith(team: newId);
                  await localRepo.updateUserProfile(updatedUser);

                  // If this is the current user, update userNotifier
                  if (updatedUser.id == widget.currentUser?.id) {
                    userNotifier.value = updatedUser;
                    await UserStorageHelper.saveUser(updatedUser);
                  }
                }
              } else {
                // Just update the name
                final updatedTeam = team.copyWith(name: newName);
                await teamRepo.upsert(updatedTeam);
              }

              // Notify other parts of the app to reload team data
              teamDataChangedNotifier.value++;
              widget.onDataChanged();

              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Équipe modifiée avec succès')),
              );
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _showEditTeamColorDialog(Team team) {
    Color selectedColor = team.color;

    // Predefined colors
    final colors = [
      const Color(0xFFE53935), // red
      const Color(0xFF1E88E5), // blue
      const Color(0xFF43A047), // green
      const Color(0xFFF9A825), // amber/yellow
      const Color(0xFF8E24AA), // purple
      const Color(0xFFFF6F00), // orange
      const Color(0xFF00897B), // teal
      const Color(0xFFD81B60), // pink
      const Color(0xFF5E35B1), // deep purple
      const Color(0xFF3949AB), // indigo
      const Color(0xFF6D4C41), // brown
      const Color(0xFF546E7A), // blue grey
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Modifier la couleur de l\'équipe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Preview
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: selectedColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
              ),
              const SizedBox(height: 24),
              // Color grid
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colors.map((color) {
                  final isSelected = selectedColor == color;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedColor = color;
                      });
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Colors.black
                              : Colors.grey.shade300,
                          width: isSelected ? 3 : 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                // Update team color
                final updatedTeam = team.copyWith(color: selectedColor);
                final teamRepo = TeamRepository();
                await teamRepo.upsert(updatedTeam);

                // Notify other parts of the app to reload team data
                teamDataChangedNotifier.value++;
                widget.onDataChanged();

                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Couleur de l\'équipe modifiée'),
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteTeamDialog(Team team) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l\'équipe'),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer ${team.name} ? Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              // Delete team directly from Firestore
              await TeamRepository().delete(team.id);

              // Notify other parts of the app to reload team data
              teamDataChangedNotifier.value++;
              widget.onDataChanged();

              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('${team.name} supprimée')));
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

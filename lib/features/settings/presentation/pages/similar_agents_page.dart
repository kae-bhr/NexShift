import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/truck_repository.dart';
import 'package:nexshift_app/core/services/wave_calculation_service.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Classe pour représenter un agent avec son score de similarité
class AgentWithSimilarity {
  final User user;
  final int wave;
  final double similarity;
  final int totalPoints; // Points totaux de criticité

  AgentWithSimilarity({
    required this.user,
    required this.wave,
    required this.similarity,
    required this.totalPoints,
  });
}

/// Page affichant tous les agents avec leur score de similarité par rapport à l'utilisateur courant
/// Organisé par vagues de notification
class SimilarAgentsPage extends StatefulWidget {
  /// Si fourni, affiche les similarités pour cet agent spécifique
  /// Sinon, affiche les similarités pour l'utilisateur connecté
  final User? targetUser;

  const SimilarAgentsPage({super.key, this.targetUser});

  @override
  State<SimilarAgentsPage> createState() => _SimilarAgentsPageState();
}

class _SimilarAgentsPageState extends State<SimilarAgentsPage> {
  bool _isLoading = true;
  User? _currentUser;
  List<AgentWithSimilarity> _agents = [];
  Map<String, int> _skillWeights = {}; // Poids de chaque compétence
  int _currentUserTotalPoints = 0; // Points totaux de l'utilisateur courant
  final _waveCalculationService = WaveCalculationService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Utiliser targetUser si fourni, sinon l'utilisateur connecté
    final currentUser = widget.targetUser ?? userNotifier.value;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    final repo = LocalRepository();
    final allUsers = await repo.getAllUsers();

    // Filtrer pour ne garder que les agents de la même station
    final stationUsers = allUsers
        .where((u) => u.station == currentUser.station && u.id != currentUser.id)
        .toList();

    // Charger les véhicules de la station pour le calcul contextuel
    final truckRepo = TruckRepository();
    final stationVehicles = await truckRepo.getByStation(currentUser.station);

    // Calculer les poids de rareté avec contexte opérationnel
    final skillWeights = await _waveCalculationService.calculateSkillRarityWeightsWithContext(
      requester: currentUser,
      teamMembers: allUsers,
      stationVehicles: stationVehicles,
      stationId: currentUser.station,
    );

    // Calculer les points totaux de l'utilisateur courant
    int currentUserPoints = 0;
    for (final skill in currentUser.skills) {
      currentUserPoints += skillWeights[skill] ?? 0;
    }

    // Calculer la vague et la similarité pour chaque agent
    final agentsWithSimilarity = <AgentWithSimilarity>[];
    for (final user in stationUsers) {
      final wave = _waveCalculationService.calculateWave(
        requester: currentUser,
        candidate: user,
        planningTeam: currentUser.team,
        agentsInPlanning: [], // On simule sans planning actif
        skillRarityWeights: skillWeights,
      );

      // Calculer la similarité
      final similarity = _calculateSkillSimilarity(
        currentUser,
        user,
        skillWeights,
      );

      // Calculer les points totaux de cet agent
      int agentTotalPoints = 0;
      for (final skill in user.skills) {
        agentTotalPoints += skillWeights[skill] ?? 0;
      }

      agentsWithSimilarity.add(AgentWithSimilarity(
        user: user,
        wave: wave,
        similarity: similarity,
        totalPoints: agentTotalPoints,
      ));
    }

    // Trier par vague, puis par similarité décroissante
    agentsWithSimilarity.sort((a, b) {
      if (a.wave != b.wave) return a.wave.compareTo(b.wave);
      return b.similarity.compareTo(a.similarity);
    });

    setState(() {
      _currentUser = currentUser;
      _agents = agentsWithSimilarity;
      _skillWeights = skillWeights;
      _currentUserTotalPoints = currentUserPoints;
      _isLoading = false;
    });
  }

  /// Détails du calcul de similarité pour affichage dans les tooltips
  String _getSimilarityExplanation(
    User user1,
    User user2,
    Map<String, int> skillWeights,
    double similarity,
  ) {
    final skills1 = Set<String>.from(user1.skills);
    final skills2 = Set<String>.from(user2.skills);

    if (skills1.isEmpty) return 'Aucune compétence à comparer';

    // Calculer le poids total des compétences de user1
    double totalWeight = 0.0;
    for (final skill in skills1) {
      totalWeight += (skillWeights[skill] ?? 0).toDouble();
    }

    if (totalWeight == 0) {
      return skills2.containsAll(skills1)
          ? 'Compétences identiques (non requises pour les véhicules)'
          : 'Aucune compétence en commun';
    }

    // Calculer le poids des compétences en commun
    double matchedWeight = 0.0;
    for (final skill in skills1) {
      if (skills2.contains(skill)) {
        matchedWeight += (skillWeights[skill] ?? 0).toDouble();
      }
    }

    // Calculer le poids des compétences supplémentaires
    double extraWeight = 0.0;
    final extraSkills = skills2.difference(skills1);
    for (final skill in extraSkills) {
      extraWeight += (skillWeights[skill] ?? 0).toDouble();
    }

    // Calculer la pénalité
    final overqualificationRatio = totalWeight > 0 ? extraWeight / totalWeight : 0.0;
    final overqualificationPenalty = (overqualificationRatio * 0.1).clamp(0.0, 0.3);
    final baseSimilarity = matchedWeight / totalWeight;

    // Formater l'explication
    final buffer = StringBuffer();
    buffer.writeln('📊 Détails du calcul de similarité\n');
    buffer.writeln('Points en commun : ${matchedWeight.round()} pts');
    buffer.writeln('Points requis : ${totalWeight.round()} pts');
    buffer.writeln('Similarité de base : ${(baseSimilarity * 100).round()}%\n');

    if (extraWeight > 0) {
      buffer.writeln('Points supplémentaires : ${extraWeight.round()} pts');
      buffer.writeln('Ratio de surqualification : ${(overqualificationRatio * 100).round()}%');
      buffer.writeln('Pénalité appliquée : -${(overqualificationPenalty * 100).round()}%\n');
    }

    buffer.writeln('═══════════════════');
    buffer.write('Similarité finale : ${(similarity * 100).round()}%');

    return buffer.toString();
  }

  /// Calcule la similarité entre deux utilisateurs basée sur leurs compétences
  ///
  /// La similarité mesure à quel point user2 peut remplacer user1 :
  /// - 100% = match parfait (user2 a exactement les compétences de user1)
  /// - 0% = aucune compétence en commun
  ///
  /// Avec le nouveau système de points (0-100) :
  /// - Les compétences rares et critiques ont des poids élevés
  /// - La similarité reflète la capacité de remplacement opérationnel
  /// - Pénalité de surqualification pour préserver les agents très qualifiés
  double _calculateSkillSimilarity(
    User user1,
    User user2,
    Map<String, int> skillWeights,
  ) {
    final skills1 = Set<String>.from(user1.skills);
    final skills2 = Set<String>.from(user2.skills);

    if (skills1.isEmpty) return 0.0;

    // Calculer le poids total des compétences de user1
    double totalWeight = 0.0;
    for (final skill in skills1) {
      totalWeight += (skillWeights[skill] ?? 0).toDouble();
    }

    // Si user1 n'a que des compétences non requises (poids 0),
    // retourner 100% si user2 les a aussi, 0% sinon
    if (totalWeight == 0) {
      return skills2.containsAll(skills1) ? 1.0 : 0.0;
    }

    // Calculer le poids des compétences en commun
    double matchedWeight = 0.0;
    for (final skill in skills1) {
      if (skills2.contains(skill)) {
        matchedWeight += (skillWeights[skill] ?? 0).toDouble();
      }
    }

    // Calculer le poids des compétences supplémentaires (surqualification)
    double extraWeight = 0.0;
    final extraSkills = skills2.difference(skills1);
    for (final skill in extraSkills) {
      extraWeight += (skillWeights[skill] ?? 0).toDouble();
    }

    // Pénalité de surqualification basée sur le ratio de compétences supplémentaires
    // Si le candidat a beaucoup de compétences rares supplémentaires,
    // il devrait être réservé pour des remplacements plus critiques
    double overqualificationPenalty = 0.0;
    if (totalWeight > 0) {
      // Ratio de surqualification : combien de points supplémentaires vs requis
      final overqualificationRatio = extraWeight / totalWeight;

      // Pénalité progressive :
      // - Si candidat a 50% de points en plus : -5% de similarité
      // - Si candidat a 100% de points en plus : -10% de similarité
      // - Si candidat a 200% de points en plus : -20% de similarité
      // - Plafonné à -30% maximum
      overqualificationPenalty = (overqualificationRatio * 0.1).clamp(0.0, 0.3);
    }

    final baseSimilarity = matchedWeight / totalWeight;
    final adjustedSimilarity = baseSimilarity - overqualificationPenalty;

    return adjustedSimilarity.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: "Agents similaires",
        bottomColor: KColors.appNameColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentUser == null
              ? const Center(child: Text('Utilisateur non connecté'))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // En-tête avec info utilisateur courant
                      _buildCurrentUserHeader(),
                      const SizedBox(height: 24),

                      // Légende des vagues
                      _buildWaveLegend(),
                      const SizedBox(height: 24),

                      // Liste des agents par vague
                      ..._buildAgentsByWave(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCurrentUserHeader() {
    return FutureBuilder(
      future: _currentUser!.team.isNotEmpty
          ? TeamRepository().getById(_currentUser!.team)
          : Future.value(null),
      builder: (context, snapshot) {
        final team = snapshot.data;
        final teamColor = team?.color ?? Colors.grey;

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: teamColor.withOpacity(0.2),
                      child: Text(
                        '${_currentUser!.firstName[0]}${_currentUser!.lastName[0]}',
                        style: TextStyle(
                          color: teamColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_currentUser!.firstName} ${_currentUser!.lastName}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Équipe ${_currentUser!.team}',
                            style: TextStyle(
                              color: teamColor,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_currentUser!.skills.length} compétence(s) - $_currentUserTotalPoints points',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Trouvez les agents les plus similaires pour un remplacement optimal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaveLegend() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Vagues de notification',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildWaveLegendItem(
              1,
              'Même équipe',
              Colors.purple,
              'Agents de votre équipe (hors astreinte)',
            ),
            _buildWaveLegendItem(
              2,
              'Compétences identiques',
              Colors.green,
              'Exactement les mêmes compétences',
            ),
            _buildWaveLegendItem(
              3,
              'Très similaires (80%+)',
              Colors.blue,
              'Compétences très proches',
            ),
            _buildWaveLegendItem(
              4,
              'Similaires (60%+)',
              Colors.orange,
              'Compétences relativement proches',
            ),
            _buildWaveLegendItem(
              5,
              'Autres agents',
              Colors.grey,
              'Tous les autres agents disponibles',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveLegendItem(
    int wave,
    String title,
    Color color,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                '$wave',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAgentsByWave() {
    final widgets = <Widget>[];

    // Grouper les agents par vague
    final agentsByWave = <int, List<AgentWithSimilarity>>{};
    for (final agent in _agents) {
      if (agent.wave == 0) continue; // Ignorer la vague 0 (agents en astreinte)
      agentsByWave.putIfAbsent(agent.wave, () => []).add(agent);
    }

    // Créer une section pour chaque vague
    final sortedWaves = agentsByWave.keys.toList()..sort();
    for (final wave in sortedWaves) {
      final agents = agentsByWave[wave]!;
      widgets.add(_buildWaveSection(wave, agents));
      widgets.add(const SizedBox(height: 16));
    }

    if (widgets.isEmpty) {
      widgets.add(
        const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Text(
              'Aucun agent trouvé',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildWaveSection(int wave, List<AgentWithSimilarity> agents) {
    final waveColors = {
      1: Colors.purple,
      2: Colors.green,
      3: Colors.blue,
      4: Colors.orange,
      5: Colors.grey,
    };

    final waveTitles = {
      1: 'Vague 1 - Même équipe',
      2: 'Vague 2 - Compétences identiques',
      3: 'Vague 3 - Très similaires (80%+)',
      4: 'Vague 4 - Similaires (60%+)',
      5: 'Vague 5 - Autres agents',
    };

    final color = waveColors[wave] ?? Colors.grey;
    final title = waveTitles[wave] ?? 'Vague $wave';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$wave',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${agents.length}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...agents.map((agent) => _buildAgentCard(agent, color)),
      ],
    );
  }

  Widget _buildAgentCard(AgentWithSimilarity agentSimilarity, Color waveColor) {
    final agent = agentSimilarity.user;
    final similarity = agentSimilarity.similarity;

    return FutureBuilder(
      future: agent.team.isNotEmpty
          ? TeamRepository().getById(agent.team)
          : Future.value(null),
      builder: (context, snapshot) {
        final team = snapshot.data;
        final teamColor = team?.color ?? Colors.grey;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => _showAgentDetails(agentSimilarity),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: teamColor.withOpacity(0.2),
                    child: Text(
                      '${agent.firstName[0]}${agent.lastName[0]}',
                      style: TextStyle(
                        color: teamColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${agent.firstName} ${agent.lastName}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.groups, size: 12, color: teamColor),
                            const SizedBox(width: 4),
                            Text(
                              'Équipe ${agent.team}',
                              style: TextStyle(
                                fontSize: 11,
                                color: teamColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.workspace_premium,
                              size: 12,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${agent.skills.length}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      // Barre de progression circulaire
                      Tooltip(
                        message: _getSimilarityExplanation(
                          _currentUser!,
                          agent,
                          _skillWeights,
                          similarity,
                        ),
                        preferBelow: false,
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: similarity,
                                backgroundColor: Colors.grey[300],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  waveColor,
                                ),
                                strokeWidth: 4,
                              ),
                              Text(
                                '${(similarity * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: waveColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAgentDetails(AgentWithSimilarity agentSimilarity) {
    final agent = agentSimilarity.user;
    final similarity = agentSimilarity.similarity;
    final wave = agentSimilarity.wave;

    final currentSkills = Set<String>.from(_currentUser!.skills);
    final agentSkills = Set<String>.from(agent.skills);
    final commonSkills = currentSkills.intersection(agentSkills).toList()..sort();
    final onlyCurrentSkills = currentSkills.difference(agentSkills).toList()..sort();
    final onlyAgentSkills = agentSkills.difference(currentSkills).toList()..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder(
              future: agent.team.isNotEmpty
                  ? TeamRepository().getById(agent.team)
                  : Future.value(null),
              builder: (context, snapshot) {
                final team = snapshot.data;
                final teamColor = team?.color ?? Colors.grey;

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // En-tête agent
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: teamColor.withOpacity(0.2),
                          child: Text(
                            '${agent.firstName[0]}${agent.lastName[0]}',
                            style: TextStyle(
                              color: teamColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${agent.firstName} ${agent.lastName}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Équipe ${agent.team}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: teamColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${agentSimilarity.totalPoints} points',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),

                    // Score de similarité
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getWaveColor(wave).withOpacity(0.1),
                            _getWaveColor(wave).withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getWaveColor(wave).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Tooltip(
                            message: _getSimilarityExplanation(
                              _currentUser!,
                              agentSimilarity.user,
                              _skillWeights,
                              similarity,
                            ),
                            preferBelow: true,
                            child: Column(
                              children: [
                                Text(
                                  '${(similarity * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: _getWaveColor(wave),
                                  ),
                                ),
                                const Text(
                                  'Similarité',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey[300],
                          ),
                          Column(
                            children: [
                              Text(
                                'Vague $wave',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: _getWaveColor(wave),
                                ),
                              ),
                              Text(
                                _getWaveTitle(wave),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Compétences en commun
                    if (commonSkills.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[600], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Compétences en commun (${commonSkills.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: commonSkills.map((skill) {
                          final skillLevelColor = KSkills.skillColors[skill];
                          final skillColor = skillLevelColor != null
                              ? KSkills.getColorForSkillLevel(skillLevelColor, context)
                              : Colors.grey;
                          final skillPoints = _skillWeights[skill] ?? 0;

                          return Tooltip(
                            message: '$skill : $skillPoints points',
                            child: Chip(
                              label: Text(
                                skill,
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: skillColor.withOpacity(0.2),
                              side: BorderSide(color: skillColor),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Compétences manquantes
                    if (onlyCurrentSkills.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.remove_circle, color: Colors.red[600], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Compétences manquantes (${onlyCurrentSkills.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: onlyCurrentSkills.map((skill) {
                          final skillLevelColor = KSkills.skillColors[skill];
                          final skillColor = skillLevelColor != null
                              ? KSkills.getColorForSkillLevel(skillLevelColor, context)
                              : Colors.grey;
                          final skillPoints = _skillWeights[skill] ?? 0;

                          return GestureDetector(
                            onTap: () {
                              // Afficher une info-bulle avec les points
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('$skill : $skillPoints points'),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                  width: 200,
                                ),
                              );
                            },
                            child: Chip(
                              label: Text(
                                skill,
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: skillColor.withOpacity(0.1),
                              side: BorderSide(color: skillColor.withOpacity(0.3)),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Compétences supplémentaires
                    if (onlyAgentSkills.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.add_circle, color: Colors.blue[600], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Compétences supplémentaires (${onlyAgentSkills.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: onlyAgentSkills.map((skill) {
                          final skillLevelColor = KSkills.skillColors[skill];
                          final skillColor = skillLevelColor != null
                              ? KSkills.getColorForSkillLevel(skillLevelColor, context)
                              : Colors.grey;
                          final skillPoints = _skillWeights[skill] ?? 0;

                          return Tooltip(
                            message: '$skill : $skillPoints points',
                            child: Chip(
                              label: Text(
                                skill,
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: skillColor.withOpacity(0.2),
                              side: BorderSide(color: skillColor),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    // Bouton pour voir les similarités de cet agent
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // Close current bottom sheet
                          // Navigate to SimilarAgentsPage with this agent
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SimilarAgentsPage(
                                targetUser: agent,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.people_alt),
                        label: const Text('Voir les agents similaires'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Color _getWaveColor(int wave) {
    const waveColors = {
      1: Colors.purple,
      2: Colors.green,
      3: Colors.blue,
      4: Colors.orange,
      5: Colors.grey,
    };
    return waveColors[wave] ?? Colors.grey;
  }

  String _getWaveTitle(int wave) {
    const waveTitles = {
      1: 'Même équipe',
      2: 'Identiques',
      3: 'Très similaires',
      4: 'Similaires',
      5: 'Autres',
    };
    return waveTitles[wave] ?? 'Vague $wave';
  }
}

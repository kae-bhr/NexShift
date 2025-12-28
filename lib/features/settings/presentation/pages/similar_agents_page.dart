import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/services/wave_calculation_service.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Classe pour représenter un agent avec son score de similarité
class AgentWithSimilarity {
  final User user;
  final int wave;
  final double similarity;
  final double totalPoints; // Points totaux de criticité

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
  Map<String, double> _skillWeights = {}; // Poids de chaque compétence
  double _currentUserTotalPoints =
      0.0; // Points totaux de l'utilisateur courant
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

    final userRepo = UserRepository();
    final allUsers = await userRepo.getByStation(currentUser.station);

    // Filtrer pour exclure l'utilisateur courant
    final stationUsers = allUsers.where((u) => u.id != currentUser.id).toList();

    // Charger la configuration de la station pour obtenir les skillWeights
    final stationRepo = StationRepository();
    final station = await stationRepo.getById(currentUser.station);
    final stationSkillWeights = station?.skillWeights ?? {};

    // Convertir les skillWeights en Map<String, double> pour compatibilité
    // Utilisation UNIQUEMENT des poids configurés dans l'AdminPage (poids de base = 1.0)
    final skillWeights = <String, double>{};

    // Récupérer toutes les compétences possibles
    final allPossibleSkills = <String>{};
    for (final user in allUsers) {
      allPossibleSkills.addAll(user.skills);
    }

    // Appliquer la pondération de la station (poids de base × pondération)
    for (final skill in allPossibleSkills) {
      final baseWeight =
          1.0; // Poids de base standard pour toutes les compétences
      final stationMultiplier = stationSkillWeights[skill] ?? 1.0;
      skillWeights[skill] = baseWeight * stationMultiplier;
    }

    // Calculer les points totaux de l'utilisateur courant
    double currentUserPoints = 0.0;
    for (final skill in currentUser.skills) {
      currentUserPoints += skillWeights[skill] ?? 0.0;
    }

    // Convertir skillWeights en Map<String, int> pour compatibilité avec calculateWave
    // (multiplication par 100 pour conserver la précision)
    final skillWeightsInt = <String, int>{};
    for (final entry in skillWeights.entries) {
      skillWeightsInt[entry.key] = (entry.value * 100).round();
    }

    // Calculer la vague et la similarité pour chaque agent
    final agentsWithSimilarity = <AgentWithSimilarity>[];
    for (final user in stationUsers) {
      final wave = _waveCalculationService.calculateWave(
        requester: currentUser,
        candidate: user,
        planningTeam: currentUser.team,
        agentsInPlanning: [], // On simule sans planning actif
        skillRarityWeights: skillWeightsInt,
        stationSkillWeights: stationSkillWeights,
      );

      // Calculer la similarité avec les poids configurés
      final similarity = _calculateSkillSimilarity(
        currentUser,
        user,
        skillWeights,
      );

      // Calculer les points totaux de cet agent
      double agentTotalPoints = 0.0;
      for (final skill in user.skills) {
        agentTotalPoints += skillWeights[skill] ?? 0.0;
      }

      agentsWithSimilarity.add(
        AgentWithSimilarity(
          user: user,
          wave: wave,
          similarity: similarity,
          totalPoints: agentTotalPoints,
        ),
      );
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

  /// Détails du calcul de compatibilité pour affichage dans les tooltips
  String _getSimilarityExplanation(
    User user1,
    User user2,
    Map<String, double> skillWeights,
    double compatibility,
  ) {
    final skills1 = Set<String>.from(user1.skills);
    final skills2 = Set<String>.from(user2.skills);

    if (skills1.isEmpty) return 'Aucune compétence à comparer';

    // Calculer le poids total des compétences de user1 (requises)
    double totalWeightUser1 = 0.0;
    for (final skill in skills1) {
      totalWeightUser1 += skillWeights[skill] ?? 0.0;
    }

    // Calculer le poids total des compétences de user2 (candidat)
    double totalWeightUser2 = 0.0;
    for (final skill in skills2) {
      totalWeightUser2 += skillWeights[skill] ?? 0.0;
    }

    if (totalWeightUser1 == 0) {
      return skills2.containsAll(skills1)
          ? 'Compétences identiques (non requises)'
          : 'Aucune compétence en commun';
    }

    // Calculer le poids des compétences en commun
    double matchedWeight = 0.0;
    for (final skill in skills1) {
      if (skills2.contains(skill)) {
        matchedWeight += skillWeights[skill] ?? 0.0;
      }
    }

    // Calculer les ratios
    final coverage = matchedWeight / totalWeightUser1;
    final precision = totalWeightUser2 > 0 ? matchedWeight / totalWeightUser2 : 0.0;

    // Formater l'explication
    final buffer = StringBuffer();
    buffer.writeln('📊 Détails du calcul de compatibilité\n');
    buffer.writeln('Points requis : ${totalWeightUser1.toStringAsFixed(1)} pts');
    buffer.writeln('Points de l\'agent : ${totalWeightUser2.toStringAsFixed(1)} pts');
    buffer.writeln('Points en commun : ${matchedWeight.toStringAsFixed(1)} pts\n');
    buffer.writeln('Couverture des besoins : ${(coverage * 100).round()}%');
    buffer.writeln('Précision du profil : ${(precision * 100).round()}%');
    buffer.writeln('═══════════════════');
    buffer.write('Compatibilité finale : ${(compatibility * 100).round()}%');

    return buffer.toString();
  }

  /// Calcule la similarité entre deux utilisateurs basée sur leurs compétences
  ///
  /// La compatibilité mesure à quel point user2 peut remplacer user1 :
  /// - 100% = match parfait (user2 a exactement les compétences de user1)
  /// - 0% = aucune compatibilité
  ///
  /// Système bidirectionnel qui pénalise autant la surqualification que la sous-qualification :
  /// - Couverture : user2 possède-t-il ce que user1 demande ?
  /// - Précision : user2 ne possède-t-il que ce que user1 demande ?
  /// - Compatibilité : moyenne des deux ratios
  double _calculateSkillSimilarity(
    User user1,
    User user2,
    Map<String, double> skillWeights,
  ) {
    final skills1 = Set<String>.from(user1.skills);
    final skills2 = Set<String>.from(user2.skills);

    if (skills1.isEmpty) return 0.0;

    // Calculer le poids total des compétences de user1 (compétences requises)
    double totalWeightUser1 = 0.0;
    for (final skill in skills1) {
      totalWeightUser1 += skillWeights[skill] ?? 0.0;
    }

    // Calculer le poids total des compétences de user2 (compétences du candidat)
    double totalWeightUser2 = 0.0;
    for (final skill in skills2) {
      totalWeightUser2 += skillWeights[skill] ?? 0.0;
    }

    // Si user1 n'a que des compétences non requises (poids 0),
    // retourner 100% si user2 les a aussi, 0% sinon
    if (totalWeightUser1 == 0) {
      return skills2.containsAll(skills1) ? 1.0 : 0.0;
    }

    // Calculer le poids des compétences en commun
    double matchedWeight = 0.0;
    for (final skill in skills1) {
      if (skills2.contains(skill)) {
        matchedWeight += skillWeights[skill] ?? 0.0;
      }
    }

    // Ratio 1 : Couverture des besoins (user2 a-t-il ce que user1 demande ?)
    final coverage = matchedWeight / totalWeightUser1;

    // Ratio 2 : Précision du profil (user2 n'a-t-il que ce que user1 demande ?)
    // Si user2 n'a aucune compétence pondérée, précision = 0
    final precision = totalWeightUser2 > 0 ? matchedWeight / totalWeightUser2 : 0.0;

    // Compatibilité finale : moyenne des deux ratios
    final compatibility = (coverage + precision) / 2;

    return compatibility.clamp(0.0, 1.0);
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
          ? TeamRepository().getById(
              _currentUser!.team,
              stationId: _currentUser!.station,
            )
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
                            style: TextStyle(color: teamColor, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_currentUser!.skills.length} compétence(s) - ${_currentUserTotalPoints.toStringAsFixed(1)} points',
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildWaveLegendItem(
              1,
              'Même équipe',
              Colors.purple,
              'Agents de votre équipe',
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
              Colors.brown,
              'Tous les autres agents disponibles',
            ),
            _buildWaveLegendItem(
              6,
              'Agents non notifiés',
              Colors.grey,
              'Ne possèdent pas la ou les compétences clés',
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
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
      // Inclure toutes les vagues, y compris la vague 0 (agents non-notifiés)
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
      0: Colors.grey,
      1: Colors.purple,
      2: Colors.green,
      3: Colors.blue,
      4: Colors.orange,
      5: Colors.brown,
    };

    final waveTitles = {
      0: 'Agents non-notifiés',
      1: 'Vague 1 - Même équipe',
      2: 'Vague 2 - Compétences identiques',
      3: 'Vague 3 - Très similaires (80%+)',
      4: 'Vague 4 - Similaires (60%+)',
      5: 'Vague 5 - Autres agents',
    };

    final waveDescriptions = {
      0: 'Agents en astreinte, remplaçants ou ne possédant pas toutes les compétences clés.',
    };

    final color = waveColors[wave] ?? Colors.grey;
    final title = waveTitles[wave] ?? 'Vague $wave';
    final description = waveDescriptions[wave];

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
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
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
          ? TeamRepository().getById(agent.team, stationId: agent.station)
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
                              style: TextStyle(fontSize: 11, color: teamColor),
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
    final commonSkills = currentSkills.intersection(agentSkills).toList()
      ..sort();
    // Filtrer les compétences à pondération 0 des listes "manquantes" et "supplémentaires"
    final onlyCurrentSkills = currentSkills.difference(agentSkills)
        .where((skill) => (_skillWeights[skill] ?? 1.0) > 0.0)
        .toList()
      ..sort();
    final onlyAgentSkills = agentSkills.difference(currentSkills)
        .where((skill) => (_skillWeights[skill] ?? 1.0) > 0.0)
        .toList()
      ..sort();

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
                  ? TeamRepository().getById(
                      agent.team,
                      stationId: agent.station,
                    )
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
                                '${agentSimilarity.totalPoints.toStringAsFixed(1)} points',
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
                                  'Compatibilité',
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
                          Icon(
                            Icons.check_circle,
                            color: Colors.green[600],
                            size: 20,
                          ),
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
                              ? KSkills.getColorForSkillLevel(
                                  skillLevelColor,
                                  context,
                                )
                              : Colors.grey;
                          final skillPoints = _skillWeights[skill] ?? 0.0;

                          return Tooltip(
                            message: '$skill : ${skillPoints.toStringAsFixed(1)} points',
                            child: Chip(
                              label: Text(
                                skill,
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: skillColor.withOpacity(0.2),
                              side: BorderSide(color: skillColor),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
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
                          Icon(
                            Icons.remove_circle,
                            color: Colors.red[600],
                            size: 20,
                          ),
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
                              ? KSkills.getColorForSkillLevel(
                                  skillLevelColor,
                                  context,
                                )
                              : Colors.grey;
                          final skillPoints = _skillWeights[skill] ?? 0.0;

                          return Tooltip(
                            message: '$skill : ${skillPoints.toStringAsFixed(1)} points',
                            child: Chip(
                              label: Text(
                                skill,
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: skillColor.withOpacity(0.1),
                              side: BorderSide(
                                color: skillColor.withOpacity(0.3),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
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
                          Icon(
                            Icons.add_circle,
                            color: Colors.blue[600],
                            size: 20,
                          ),
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
                              ? KSkills.getColorForSkillLevel(
                                  skillLevelColor,
                                  context,
                                )
                              : Colors.grey;
                          final skillPoints = _skillWeights[skill] ?? 0.0;

                          return Tooltip(
                            message: '$skill : ${skillPoints.toStringAsFixed(1)} points',
                            child: Chip(
                              label: Text(
                                skill,
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: skillColor.withOpacity(0.2),
                              side: BorderSide(color: skillColor),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
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
                              builder: (context) =>
                                  SimilarAgentsPage(targetUser: agent),
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
      0: Colors.grey,
      1: Colors.purple,
      2: Colors.green,
      3: Colors.blue,
      4: Colors.orange,
      5: Colors.brown,
    };
    return waveColors[wave] ?? Colors.grey;
  }

  String _getWaveTitle(int wave) {
    const waveTitles = {
      0: 'Non notifiés',
      1: 'Même équipe',
      2: 'Identiques',
      3: 'Très similaires',
      4: 'Similaires',
      5: 'Autres',
    };
    return waveTitles[wave] ?? 'Vague $wave';
  }
}

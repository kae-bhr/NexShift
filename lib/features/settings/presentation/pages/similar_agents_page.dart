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
  final double totalPoints;

  AgentWithSimilarity({
    required this.user,
    required this.wave,
    required this.similarity,
    required this.totalPoints,
  });
}

/// Page affichant tous les agents avec leur score de similarité par rapport à l'utilisateur courant
class SimilarAgentsPage extends StatefulWidget {
  final User? targetUser;

  const SimilarAgentsPage({super.key, this.targetUser});

  @override
  State<SimilarAgentsPage> createState() => _SimilarAgentsPageState();
}

class _SimilarAgentsPageState extends State<SimilarAgentsPage> {
  bool _isLoading = true;
  User? _currentUser;
  List<AgentWithSimilarity> _agents = [];
  Map<String, double> _skillWeights = {};
  double _currentUserTotalPoints = 0.0;
  final _waveCalculationService = WaveCalculationService();

  // Couleurs des vagues — constantes partagées
  static const Map<int, Color> _waveColors = {
    0: Colors.grey,
    1: Colors.purple,
    2: Colors.green,
    3: Colors.blue,
    4: Colors.orange,
    5: Colors.brown,
  };

  static const Map<int, String> _waveTitles = {
    0: 'Non notifiés',
    1: 'Même équipe',
    2: 'Identiques',
    3: 'Très similaires',
    4: 'Similaires',
    5: 'Autres',
  };

  static const Map<int, String> _waveFullTitles = {
    0: 'Agents non notifiés',
    1: 'Vague 1 — Même équipe',
    2: 'Vague 2 — Compétences identiques',
    3: 'Vague 3 — Très similaires (80%+)',
    4: 'Vague 4 — Similaires (60%+)',
    5: 'Vague 5 — Autres agents',
  };

  static const Map<int, String> _waveDescriptions = {
    0: 'Agents en astreinte, remplaçants ou ne possédant pas toutes les compétences clés.',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final currentUser = widget.targetUser ?? userNotifier.value;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    final userRepo = UserRepository();
    final allUsers = await userRepo.getByStation(currentUser.station);
    final stationUsers = allUsers.where((u) => u.id != currentUser.id).toList();

    final stationRepo = StationRepository();
    final station = await stationRepo.getById(currentUser.station);
    final stationSkillWeights = station?.skillWeights ?? {};

    final skillWeights = <String, double>{};
    final allPossibleSkills = <String>{};
    for (final user in allUsers) {
      allPossibleSkills.addAll(user.skills);
    }
    for (final skill in allPossibleSkills) {
      const baseWeight = 1.0;
      final stationMultiplier = stationSkillWeights[skill] ?? 1.0;
      skillWeights[skill] = baseWeight * stationMultiplier;
    }

    double currentUserPoints = 0.0;
    for (final skill in currentUser.skills) {
      currentUserPoints += skillWeights[skill] ?? 0.0;
    }

    final skillWeightsInt = <String, int>{};
    for (final entry in skillWeights.entries) {
      skillWeightsInt[entry.key] = (entry.value * 100).round();
    }

    final agentsWithSimilarity = <AgentWithSimilarity>[];
    for (final user in stationUsers) {
      final wave = _waveCalculationService.calculateWave(
        requester: currentUser,
        candidate: user,
        planningTeam: currentUser.team,
        agentsInPlanning: [],
        skillRarityWeights: skillWeightsInt,
        stationSkillWeights: stationSkillWeights,
      );
      final similarity =
          _calculateSkillSimilarity(currentUser, user, skillWeights);
      double agentTotalPoints = 0.0;
      for (final skill in user.skills) {
        agentTotalPoints += skillWeights[skill] ?? 0.0;
      }
      agentsWithSimilarity.add(AgentWithSimilarity(
        user: user,
        wave: wave,
        similarity: similarity,
        totalPoints: agentTotalPoints,
      ));
    }

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

  double _calculateSkillSimilarity(
      User user1, User user2, Map<String, double> skillWeights) {
    final skills1 = Set<String>.from(user1.skills);
    final skills2 = Set<String>.from(user2.skills);
    if (skills1.isEmpty) return 0.0;

    double totalWeightUser1 = 0.0;
    for (final skill in skills1) {
      totalWeightUser1 += skillWeights[skill] ?? 0.0;
    }
    double totalWeightUser2 = 0.0;
    for (final skill in skills2) {
      totalWeightUser2 += skillWeights[skill] ?? 0.0;
    }

    if (totalWeightUser1 == 0) {
      return skills2.containsAll(skills1) ? 1.0 : 0.0;
    }

    double matchedWeight = 0.0;
    for (final skill in skills1) {
      if (skills2.contains(skill)) {
        matchedWeight += skillWeights[skill] ?? 0.0;
      }
    }

    final coverage = matchedWeight / totalWeightUser1;
    final precision =
        totalWeightUser2 > 0 ? matchedWeight / totalWeightUser2 : 0.0;
    return ((coverage + precision) / 2).clamp(0.0, 1.0);
  }

  String _getSimilarityExplanation(User user1, User user2,
      Map<String, double> skillWeights, double compatibility) {
    final skills1 = Set<String>.from(user1.skills);
    final skills2 = Set<String>.from(user2.skills);
    if (skills1.isEmpty) return 'Aucune compétence à comparer';

    double totalWeightUser1 = 0.0;
    for (final skill in skills1) {
      totalWeightUser1 += skillWeights[skill] ?? 0.0;
    }
    double totalWeightUser2 = 0.0;
    for (final skill in skills2) {
      totalWeightUser2 += skillWeights[skill] ?? 0.0;
    }
    if (totalWeightUser1 == 0) {
      return skills2.containsAll(skills1)
          ? 'Compétences identiques (non requises)'
          : 'Aucune compétence en commun';
    }
    double matchedWeight = 0.0;
    for (final skill in skills1) {
      if (skills2.contains(skill)) {
        matchedWeight += skillWeights[skill] ?? 0.0;
      }
    }
    final coverage = matchedWeight / totalWeightUser1;
    final precision =
        totalWeightUser2 > 0 ? matchedWeight / totalWeightUser2 : 0.0;

    final buffer = StringBuffer();
    buffer.writeln('Détails du calcul\n');
    buffer.writeln('Points requis : ${totalWeightUser1.toStringAsFixed(1)} pts');
    buffer.writeln(
        'Points de l\'agent : ${totalWeightUser2.toStringAsFixed(1)} pts');
    buffer.writeln(
        'Points en commun : ${matchedWeight.toStringAsFixed(1)} pts\n');
    buffer.writeln('Couverture : ${(coverage * 100).round()}%');
    buffer.writeln('Précision : ${(precision * 100).round()}%');
    buffer.write('Compatibilité : ${(compatibility * 100).round()}%');
    return buffer.toString();
  }

  Color _waveColor(int wave) => _waveColors[wave] ?? Colors.grey;
  String _waveTitle(int wave) => _waveTitles[wave] ?? 'Vague $wave';
  String _waveFullTitle(int wave) => _waveFullTitles[wave] ?? 'Vague $wave';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Agents similaires',
        bottomColor: KColors.appNameColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentUser == null
          ? const Center(child: Text('Utilisateur non connecté'))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _buildCurrentUserCard(isDark),
                  const SizedBox(height: 16),
                  _buildWaveLegendCard(isDark),
                  const SizedBox(height: 20),
                  ..._buildAgentsByWave(isDark),
                ],
              ),
            ),
    );
  }

  // ── Carte utilisateur courant ───────────────────────────────────────────────
  Widget _buildCurrentUserCard(bool isDark) {
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

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                KColors.appNameColor.withValues(alpha: isDark ? 0.14 : 0.08),
                KColors.appNameColor.withValues(alpha: isDark ? 0.05 : 0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: KColors.appNameColor.withValues(alpha: isDark ? 0.28 : 0.18),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: teamColor.withValues(alpha: 0.20),
                child: Text(
                  _currentUser!.initials,
                  style: TextStyle(
                    color: teamColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentUser!.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.grey.shade100 : Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: teamColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          'Équipe ${_currentUser!.team}',
                          style: TextStyle(
                            fontSize: 12,
                            color: teamColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_currentUser!.skills.length} compétences — ${_currentUserTotalPoints.toStringAsFixed(1)} pts',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Légende des vagues ──────────────────────────────────────────────────────
  Widget _buildWaveLegendCard(bool isDark) {
    final waveEntries = [
      (1, 'Même équipe', 'Agents de votre équipe'),
      (2, 'Compétences identiques', 'Exactement les mêmes compétences'),
      (3, 'Très similaires (80%+)', 'Compétences très proches'),
      (4, 'Similaires (60%+)', 'Compétences relativement proches'),
      (5, 'Autres agents', 'Tous les autres agents disponibles'),
      (0, 'Agents non notifiés', 'Ne possèdent pas les compétences clés'),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                'VAGUES DE NOTIFICATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...waveEntries.map((entry) {
            final wave = entry.$1;
            final title = entry.$2;
            final desc = entry.$3;
            final color = _waveColor(wave);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: color.withValues(alpha: 0.50)),
                    ),
                    child: Center(
                      child: Text(
                        '$wave',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.grey.shade200
                                : Colors.grey.shade800,
                          ),
                        ),
                        Text(
                          desc,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Sections par vague ──────────────────────────────────────────────────────
  List<Widget> _buildAgentsByWave(bool isDark) {
    final agentsByWave = <int, List<AgentWithSimilarity>>{};
    for (final agent in _agents) {
      agentsByWave.putIfAbsent(agent.wave, () => []).add(agent);
    }

    if (agentsByWave.isEmpty) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Aucun agent trouvé',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    final sortedWaves = agentsByWave.keys.toList()..sort();
    for (final wave in sortedWaves) {
      final agents = agentsByWave[wave]!;
      widgets.add(_buildWaveSection(wave, agents, isDark));
      widgets.add(const SizedBox(height: 16));
    }
    return widgets;
  }

  Widget _buildWaveSection(
      int wave, List<AgentWithSimilarity> agents, bool isDark) {
    final color = _waveColor(wave);
    final description = _waveDescriptions[wave];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête de vague
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.12 : 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: isDark ? 0.30 : 0.20)),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    '$wave',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _waveFullTitle(wave),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    if (description != null)
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${agents.length}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...agents
            .map((agent) => _buildAgentCard(agent, color, isDark)),
      ],
    );
  }

  Widget _buildAgentCard(
      AgentWithSimilarity agentSimilarity, Color waveColor, bool isDark) {
    final agent = agentSimilarity.user;
    final similarity = agentSimilarity.similarity;
    final pct = (similarity * 100).toInt();

    return FutureBuilder(
      future: agent.team.isNotEmpty
          ? TeamRepository().getById(agent.team, stationId: agent.station)
          : Future.value(null),
      builder: (context, snapshot) {
        final team = snapshot.data;
        final teamColor = team?.color ?? Colors.grey;

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () => _showAgentDetails(agentSimilarity),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: teamColor.withValues(alpha: 0.18),
                    child: Text(
                      agent.initials,
                      style: TextStyle(
                        color: teamColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Infos
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agent.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.grey.shade200
                                : Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: BoxDecoration(
                                color: teamColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Text(
                              'Équipe ${agent.team}',
                              style: TextStyle(
                                fontSize: 11,
                                color: teamColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.workspace_premium_rounded,
                                size: 11,
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500),
                            const SizedBox(width: 3),
                            Text(
                              '${agent.skills.length}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Gauge de compatibilité
                  Tooltip(
                    message: _getSimilarityExplanation(
                        _currentUser!, agent, _skillWeights, similarity),
                    preferBelow: false,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: similarity,
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.grey.shade200,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(waveColor),
                            strokeWidth: 3.5,
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: waveColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Détail agent (bottom sheet) ─────────────────────────────────────────────
  void _showAgentDetails(AgentWithSimilarity agentSimilarity) {
    final agent = agentSimilarity.user;
    final similarity = agentSimilarity.similarity;
    final wave = agentSimilarity.wave;

    final currentSkills = Set<String>.from(_currentUser!.skills);
    final agentSkills = Set<String>.from(agent.skills);
    final commonSkills = currentSkills.intersection(agentSkills).toList()..sort();
    final onlyCurrentSkills = currentSkills
        .difference(agentSkills)
        .where((s) => (_skillWeights[s] ?? 1.0) > 0.0)
        .toList()
      ..sort();
    final onlyAgentSkills = agentSkills
        .difference(currentSkills)
        .where((s) => (_skillWeights[s] ?? 1.0) > 0.0)
        .toList()
      ..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: FutureBuilder(
                future: agent.team.isNotEmpty
                    ? TeamRepository().getById(
                        agent.team,
                        stationId: agent.station,
                      )
                    : Future.value(null),
                builder: (context, snapshot) {
                  final team = snapshot.data;
                  final teamColor = team?.color ?? Colors.grey;
                  final waveColor = _waveColor(wave);

                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // En-tête agent
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: teamColor.withValues(alpha: 0.18),
                            child: Text(
                              agent.initials,
                              style: TextStyle(
                                color: teamColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  agent.displayName,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.grey.shade100
                                        : Colors.grey.shade900,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(right: 5),
                                      decoration: BoxDecoration(
                                        color: teamColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Text(
                                      'Équipe ${agent.team}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: teamColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${agentSimilarity.totalPoints.toStringAsFixed(1)} points',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.grey.shade500
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Score de compatibilité
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: waveColor.withValues(alpha: isDark ? 0.12 : 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: waveColor.withValues(
                                  alpha: isDark ? 0.30 : 0.20)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  '${(similarity * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: waveColor,
                                  ),
                                ),
                                Text(
                                  'Compatibilité',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: waveColor.withValues(alpha: 0.25),
                            ),
                            Column(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: waveColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$wave',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _waveTitle(wave),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Compétences en commun
                      if (commonSkills.isNotEmpty)
                        _SkillSection(
                          label: 'En commun',
                          count: commonSkills.length,
                          icon: Icons.check_circle_rounded,
                          color: Colors.green,
                          skills: commonSkills,
                          skillWeights: _skillWeights,
                          isDark: isDark,
                        ),

                      // Compétences manquantes
                      if (onlyCurrentSkills.isNotEmpty) ...[
                        if (commonSkills.isNotEmpty)
                          const SizedBox(height: 10),
                        _SkillSection(
                          label: 'Manquantes',
                          count: onlyCurrentSkills.length,
                          icon: Icons.remove_circle_rounded,
                          color: Colors.red,
                          skills: onlyCurrentSkills,
                          skillWeights: _skillWeights,
                          isDark: isDark,
                        ),
                      ],

                      // Compétences supplémentaires
                      if (onlyAgentSkills.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _SkillSection(
                          label: 'Supplémentaires',
                          count: onlyAgentSkills.length,
                          icon: Icons.add_circle_rounded,
                          color: Colors.blue,
                          skills: onlyAgentSkills,
                          skillWeights: _skillWeights,
                          isDark: isDark,
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Bouton "Voir les agents similaires de cet agent"
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  SimilarAgentsPage(targetUser: agent),
                            ),
                          );
                        },
                        icon: const Icon(Icons.people_alt_rounded, size: 18),
                        label: const Text(
                          'Agents similaires à cet agent',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: KColors.appNameColor,
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

// ── Widgets locaux ─────────────────────────────────────────────────────────────

class _SkillSection extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final List<String> skills;
  final Map<String, double> skillWeights;
  final bool isDark;

  const _SkillSection({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.skills,
    required this.skillWeights,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: color.withValues(alpha: isDark ? 0.25 : 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                '$label ($count)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: skills.map((skill) {
              final skillLevelColor = KSkills.skillColors[skill];
              final skillColor = skillLevelColor != null
                  ? KSkills.getColorForSkillLevel(skillLevelColor, context)
                  : Colors.grey;
              final pts = skillWeights[skill] ?? 0.0;

              return Tooltip(
                message: '$skill : ${pts.toStringAsFixed(1)} pts',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: skillColor.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: skillColor.withValues(alpha: 0.40)),
                  ),
                  child: Text(
                    skill,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? skillColor.withValues(alpha: 0.90)
                          : skillColor,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

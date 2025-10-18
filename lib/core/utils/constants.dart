import 'package:flutter/material.dart';

/// Enum représentant les niveaux de couleur pour les compétences
enum SkillLevelColor {
  apprentice, // Bleu
  equipier, // Primary
  teamLeader, // Orange
  chiefOfficer, // Doré
}

/// Classe représentant une compétence avec son niveau de couleur
class SkillWithLevel {
  final String name;
  final SkillLevelColor levelColor;

  const SkillWithLevel(this.name, this.levelColor);
}

class KConstants {
  static const String themeModeKey = 'themeModeKey';
  static const String authentifiedKey = 'authentifiedKey';
  static const String userKey = 'userKey';

  // user
  static const String station = 'Saint-Vaast-La-Hougue';
  static const String statusAgent = 'agent';
  static const String statusChief = 'chief';
  static const String statusLeader = 'leader';
  static const String teamA = 'A';
  static const String teamB = 'B';
  static const String teamC = 'C';
  static const String teamD = 'D';
}

class KSkills {
  static const String suap = 'SUAP';
  static const String suapCA = 'Chef d\'agrès SUAP';
  static const String suapA = 'Apprenant SUAP';
  static const String ppbe = 'PPBE';
  static const String ppbeCA = 'Chef d\'agrès PPBE';
  static const String ppbeA = 'Apprenant PPBE';
  static const String inc = 'INC';
  static const String incCE = 'Chef d\'équipe INC';
  static const String incCA = 'Chef d\'agrès INC';
  static const String incA = 'Apprenant INC';
  static const String vps = 'VPS';
  static const String vpsCA = 'Chef d\'agrès VPS';
  static const String cod0 = 'COD 0';
  static const String cod1 = 'COD 1';
  static const String cod2 = 'COD 2';

  static const List<String> listSkills = [
    suap,
    ppbe,
    inc,
    vps,
    suapCA,
    ppbeCA,
    incCE,
    incCA,
    vpsCA,
    cod0,
    cod1,
    cod2,
    suapA,
    ppbeA,
    incA,
  ];

  /// Map associant chaque compétence à son niveau de couleur
  static const Map<String, SkillLevelColor> skillColors = {
    // SUAP
    suapA: SkillLevelColor.apprentice,
    suap: SkillLevelColor.equipier,
    suapCA: SkillLevelColor.chiefOfficer,
    // PPBE
    ppbeA: SkillLevelColor.apprentice,
    ppbe: SkillLevelColor.equipier,
    ppbeCA: SkillLevelColor.chiefOfficer,
    // INC
    incA: SkillLevelColor.apprentice,
    inc: SkillLevelColor.equipier,
    incCE: SkillLevelColor.teamLeader,
    incCA: SkillLevelColor.chiefOfficer,
    // VPS
    vps: SkillLevelColor.equipier,
    vpsCA: SkillLevelColor.chiefOfficer,
    // COD
    cod0: SkillLevelColor.equipier,
    cod1: SkillLevelColor.teamLeader,
    cod2: SkillLevelColor.chiefOfficer,
  };

  /// Obtenir la couleur Flutter correspondant au niveau de compétence
  static Color getColorForSkillLevel(
    SkillLevelColor levelColor,
    BuildContext context,
  ) {
    switch (levelColor) {
      case SkillLevelColor.apprentice:
        return Colors.blue;
      case SkillLevelColor.equipier:
        return KColors.appNameColor;
      case SkillLevelColor.teamLeader:
        return Colors.orange;
      case SkillLevelColor.chiefOfficer:
        return Colors.amber;
    }
  }

  /// Obtenir le label correspondant au niveau de compétence
  static String getLabelForSkillLevel(
    SkillLevelColor levelColor,
    String category,
  ) {
    // COD a des labels spéciaux
    if (category == 'COD') {
      switch (levelColor) {
        case SkillLevelColor.equipier:
          return 'Conducteur';
        case SkillLevelColor.teamLeader:
          return 'Conducteur Poids-Lourd';
        case SkillLevelColor.chiefOfficer:
          return 'Conducteur Tout-Terrain';
        case SkillLevelColor.apprentice:
          return '';
      }
    }

    // INC a un niveau supplémentaire
    switch (levelColor) {
      case SkillLevelColor.apprentice:
        return 'Apprenant';
      case SkillLevelColor.equipier:
        return 'Équipier';
      case SkillLevelColor.teamLeader:
        return category == 'INC' ? 'Chef d\'équipe' : '';
      case SkillLevelColor.chiefOfficer:
        return 'Chef d\'agrès';
    }
  }

  /// Icons for each skill category
  static const Map<String, IconData> skillCategoryIcons = {
    'SUAP': Icons.healing_outlined,
    'PPBE': Icons.build,
    'INC': Icons.local_fire_department,
    'VPS': Icons.car_crash_sharp,
    'COD': Icons.album,
  };

  /// Skill levels hierarchy: category -> [level0 (lowest), level1, level2, level3 (highest)]
  /// Index in array represents skill level: 0=apprenant/none, 1=equipier, 2=chef d'équipe (INC only), 3=chef d'agrès
  /// Note: SUAP/PPBE use indices [0,1,3], VPS uses [1,3], INC uses [0,1,2,3], COD uses [1,2,3]
  static const Map<String, List<String>> skillLevels = {
    'SUAP': [suapA, suap, '', suapCA], // indices 0, 1, 3
    'PPBE': [ppbeA, ppbe, '', ppbeCA], // indices 0, 1, 3
    'INC': [incA, inc, incCE, incCA], // indices 0, 1, 2, 3
    'VPS': ['', vps, '', vpsCA], // indices 1, 3 (no apprentice)
    'COD': ['', cod0, cod1, cod2], // indices 0, 1, 2
  };

  /// Display order for skill categories
  static const List<String> skillCategoryOrder = [
    'SUAP',
    'PPBE',
    'INC',
    'VPS',
    'COD',
  ];
}

class KTrucks {
  static const String vsav = 'VSAV';
  static const String vtu = 'VTU';
  static const String vps = 'VPS';
  static const String fpt = 'FPT';
  static const String epa = 'EPA';
  static const String vsr = 'VSR';
  static const String ccf = 'CCF';
  static const String vss = 'VSS';
  static const String vpc = 'VPC';

  /// Display order for vehicle types
  static const List<String> vehicleTypeOrder = [
    vsav,
    vtu,
    fpt,
    vps,
    epa,
    vsr,
    ccf,
    vss,
    vpc,
  ];

  /// Sort priority for vehicle types
  static const Map<String, int> vehicleTypePriority = {
    vsav: 0,
    vtu: 1,
    fpt: 2,
    vps: 3,
    epa: 4,
    vsr: 5,
    ccf: 6,
    vss: 7,
    vpc: 8,
  };

  /// Icons associated with each vehicle type
  static const Map<String, IconData> vehicleIcons = {
    vsav: Icons.healing_outlined,
    vtu: Icons.build,
    fpt: Icons.local_fire_department,
    vps: Icons.car_crash_sharp,
    epa: Icons.stairs,
    vsr: Icons.route,
    ccf: Icons.forest,
    vss: Icons.emergency,
    vpc: Icons.supervisor_account,
  };

  /// Colors associated with each vehicle type
  static const Map<String, Color> vehicleColors = {
    vsav: Color(0xFFE53935), // Red
    vtu: Color(0xFFFB8C00), // Orange
    fpt: Color(0xFFFF5722), // Deep Orange
    vps: Color(0xFF1E88E5), // Blue
    epa: Color(0xFF5E35B1), // Deep Purple
    vsr: Color(0xFF00897B), // Teal
    ccf: Color(0xFF558B2F), // Light Green
    vss: Color(0xFFD81B60), // Pink
    vpc: Color(0xFF6D4C41), // Brown
  };

  /// Descriptions for each vehicle type
  static const Map<String, String> vehicleDescriptions = {
    vsav: 'Véhicule de Secours et d\'Assistance aux Victimes',
    vtu: 'Véhicule Toutes Utilités',
    fpt: 'Fourgon Pompe Tonne',
    vps: 'Véhicule de Premier Secours',
    epa: 'Échelle Pivotante Automatique',
    vsr: 'Véhicule de Secours Routier',
    ccf: 'Camion-Citerne Feux de Forêts',
    vss: 'Véhicule de Secours Spécialisé',
    vpc: 'Véhicule Poste de Commandement',
  };
}

class KColors {
  static const Color appNameColor = Color.fromARGB(255, 144, 74, 68);
  static Color get weak => Colors.redAccent;
  static Color get medium => Colors.orangeAccent;
  static Color get strong => Colors.greenAccent;
  static Color get undefined => Colors.grey;
}

class KTextStyle {
  static const TextStyle titleTextStyle = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.bold,
    fontFamily: 'Roboto',
  );
  static const TextStyle regularTextStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.normal,
    fontFamily: 'Roboto',
  );
  static const TextStyle descriptionTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w300,
    fontFamily: 'Roboto',
  );
}

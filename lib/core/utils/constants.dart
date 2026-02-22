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
  static const String station = 'Caserne';
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
  static const String cod2VL = 'COD 2 VL';
  static const String cod2PL = 'COD 2 PL';

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
    cod2VL,
    cod2PL,
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
    cod2VL: SkillLevelColor.chiefOfficer,
    cod2PL: SkillLevelColor.chiefOfficer,
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
        return const Color.fromARGB(255, 255, 94, 0);
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
  /// Index in array represents skill level: 0=apprenant/none, 1=equipier, 2=chef d'équipe, 3=chef d'agrès
  static const Map<String, List<String>> skillLevels = {
    'SUAP': [suapA, suap, '', suapCA], // indices 0, 1, 3
    'PPBE': [ppbeA, ppbe, '', ppbeCA], // indices 0, 1, 3
    'INC': [incA, inc, incCE, incCA], // indices 0, 1, 2, 3
    'VPS': ['', vps, '', vpsCA], // indices 1, 3
    'COD': ['', cod0, cod1, cod2VL, cod2PL], // indices 1, 2, 3, 3
  };

  /// Display order for skill categories
  static const List<String> skillCategoryOrder = [
    'SUAP',
    'PPBE',
    'INC',
    'VPS',
    'COD',
  ];

  /// Icons available for position selection (50 icons)
  static const Map<String, IconData> positionIcons = {
    // Opérationnel / Secours
    'local_fire_department': Icons.local_fire_department,
    'healing_outlined': Icons.healing_outlined,
    'emergency': Icons.emergency,
    'medical_services': Icons.medical_services,
    'medication': Icons.medication,
    'vaccines': Icons.vaccines,
    'health_and_safety': Icons.health_and_safety,
    'monitor_heart': Icons.monitor_heart,
    // Véhicules / Conduite
    'album': Icons.album,
    'car_crash_sharp': Icons.car_crash_sharp,
    'local_shipping': Icons.local_shipping,
    'directions_car': Icons.directions_car,
    'fire_truck': Icons.fire_truck,
    'airport_shuttle': Icons.airport_shuttle,
    // Technique / Matériel
    'build': Icons.build,
    'engineering': Icons.engineering,
    'handyman': Icons.handyman,
    'construction': Icons.construction,
    'plumbing': Icons.plumbing,
    'hardware': Icons.hardware,
    'inventory': Icons.inventory,
    'warehouse': Icons.warehouse,
    // Hiérarchie / Rôles
    'shield_moon': Icons.shield_moon,
    'verified_user': Icons.verified_user,
    'person': Icons.person,
    'supervisor_account': Icons.supervisor_account,
    'admin_panel_settings': Icons.admin_panel_settings,
    'military_tech': Icons.military_tech,
    'stars': Icons.stars,
    // Sport / EAP
    'fitness_center': Icons.fitness_center,
    'sports': Icons.sports,
    'sports_martial_arts': Icons.sports_martial_arts,
    'pool': Icons.pool,
    'directions_run': Icons.directions_run,
    // Environnement / Terrain
    'stairs': Icons.stairs,
    'forest': Icons.forest,
    'route': Icons.route,
    'terrain': Icons.terrain,
    'water': Icons.water,
    // Formation / Administratif
    'school': Icons.school,
    'cast_for_education': Icons.cast_for_education,
    'psychology': Icons.psychology,
    'menu_book': Icons.menu_book,
    'description': Icons.description,
    'folder': Icons.folder,
    'assignment': Icons.assignment,
    // Prévention / Sécurité
    'shield': Icons.shield,
    'security': Icons.security,
    'gpp_good': Icons.gpp_good,
    // Communication / Logistique
    'campaign': Icons.campaign,
    'phone': Icons.phone,
    'email': Icons.email,
    // Habillement
    'checkroom': Icons.checkroom,
    'shopping_bag': Icons.shopping_bag,
  };

  /// Display names for position icons
  static const Map<String, String> positionIconNames = {
    // Opérationnel / Secours
    'local_fire_department': 'Incendie',
    'healing_outlined': 'Secours',
    'emergency': 'Urgence',
    'medical_services': 'Services médicaux',
    'medication': 'Pharmacie',
    'vaccines': 'Vaccination',
    'health_and_safety': 'Santé & sécurité',
    'monitor_heart': 'Monitoring',
    // Véhicules / Conduite
    'album': 'Conduite',
    'car_crash_sharp': 'VPS',
    'local_shipping': 'Transport',
    'directions_car': 'Véhicule léger',
    'fire_truck': 'Engin incendie',
    'airport_shuttle': 'Navette',
    // Technique / Matériel
    'build': 'Technique',
    'engineering': 'Ingénierie',
    'handyman': 'Maintenance',
    'construction': 'Construction',
    'plumbing': 'Plomberie',
    'hardware': 'Outillage',
    'inventory': 'Inventaire',
    'warehouse': 'Magasin',
    // Hiérarchie / Rôles
    'shield_moon': 'Chef de centre',
    'verified_user': 'Chef de garde',
    'person': 'Agent',
    'supervisor_account': 'Encadrement',
    'admin_panel_settings': 'Administration',
    'military_tech': 'Grade',
    'stars': 'Distinction',
    // Sport / EAP
    'fitness_center': 'Sport / EAP',
    'sports': 'Activités sportives',
    'sports_martial_arts': 'Arts martiaux',
    'pool': 'Natation',
    'directions_run': 'Course',
    // Environnement / Terrain
    'stairs': 'EPA',
    'forest': 'Feux de forêt',
    'route': 'Route',
    'terrain': 'Terrain',
    'water': 'Milieu aquatique',
    // Formation / Administratif
    'school': 'Formation',
    'cast_for_education': 'Enseignement',
    'psychology': 'Psychologie',
    'menu_book': 'Documentation',
    'description': 'Rédaction',
    'folder': 'Dossiers',
    'assignment': 'Missions',
    // Prévention / Sécurité
    'shield': 'Prévention',
    'security': 'Sécurité',
    'gpp_good': 'Conformité',
    // Communication / Logistique
    'campaign': 'Communication',
    'phone': 'Téléphonie',
    'email': 'Messagerie',
    // Habillement
    'checkroom': 'Habillement',
    'shopping_bag': 'Équipements',
  };
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

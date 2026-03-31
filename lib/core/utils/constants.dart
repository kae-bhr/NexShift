import 'package:flutter/material.dart';

/// Enum représentant les niveaux de couleur pour les compétences
enum SkillLevelColor {
  apprentice, // Bleu — Niveau 0 : Apprenti
  equipier, // Primary — Niveau 1 : Équipier
  teamLeader, // Orange — Niveau 2 : Chef d'équipe
  chiefOfficer, // Doré — Niveau 3 : Chef d'agrès
  groupLeader, // Rouge profond — Niveau 4 : Chef de groupe
  columnLeader, // Violet foncé — Niveau 5 : Chef de colonne
  siteLead, // Bleu marine — Niveau 6 : Chef de site
  specialty, // Teal — Niveau 9 : Spécialité
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
  // SUAP (Secours d'Urgence aux Personnes)
  static const String suap = 'SUAP';
  static const String suapCA = 'Chef d\'agrès SUAP';
  static const String suapA = 'Apprenant SUAP';
  // PPBE (Protection des Personnes, des Biens et de l'Environnement)
  static const String ppbe = 'PPBE';
  static const String ppbeCA = 'Chef d\'agrès PPBE';
  static const String ppbeA = 'Apprenant PPBE';
  // INC (Incendie)
  static const String inc = 'INC';
  static const String incCE = 'Chef d\'équipe INC';
  static const String incCA = 'Chef d\'agrès INC';
  static const String incA = 'Apprenant INC';
  // SR (Secours Routier)
  static const String sr = 'SR';
  static const String srCA = 'Chef d\'agrès SR';
  // COD (Conducteur)
  static const String cod0 = 'COD 0';
  static const String cod1 = 'COD 1';
  static const String cod2VL = 'COD 2 VL';
  static const String cod2PL = 'COD 2 PL';
  static const String cod3 = 'COD 3';
  static const String cod4 = 'COD 4';
  static const String cod5 = 'COD 5';
  static const String cod6 = 'COD 6';
  // FDF (Feux De Forêt)
  static const String fdf1 = 'FDF 1';
  static const String fdf2 = 'FDF 2';
  static const String fdf3 = 'FDF 3';
  static const String fdf4 = 'FDF 4';
  static const String fdf5 = 'FDF 5';
  // PLG (Plongée)
  static const String plg1 = 'PLG 1';
  // RAD (Risque Radiologique)
  static const String rad1 = 'RAD 1';
  static const String rad2 = 'RAD 2';
  static const String rad3 = 'RAD 3';
  // RCH (Risque Chimique & Biologique)
  static const String rch1 = 'RCH 1';
  static const String rch2 = 'RCH 2';
  // SAV (Sauvetage Aquatique)
  static const String sav1 = 'SAV 1';
  static const String sav2 = 'SAV 2';
  static const String sav3 = 'SAV 3';
  // TRS (Transmissions)
  static const String trs1 = 'TRS 1';
  static const String trs2 = 'TRS 2';
  static const String trs3 = 'TRS 3';
  static const String trs4 = 'TRS 4';
  static const String trs5 = 'TRS 5';
  // IBNB (Intervention à Bord des Navires et des Bâteaux)
  static const String ibnb1 = 'IBNB 1';
  static const String ibnb2 = 'IBNB 2';
  static const String ibnb3 = 'IBNB 3';
  // CYNO (Cynophile)
  static const String cyno1 = 'CYNO 1';
  static const String cyno2 = 'CYNO 2';
  // Spécialités standalone
  static const String sal = 'SAL';
  static const String sh = 'SH';
  static const String usar = 'USAR';
  static const String grimp = 'GRIMP';

  static const List<String> listSkills = [
    // SUAP
    suapA, suap, suapCA,
    // PPBE
    ppbeA, ppbe, ppbeCA,
    // INC
    incA, inc, incCE, incCA,
    // SR
    sr, srCA,
    // COD
    cod0, cod1, cod2VL, cod2PL, cod3, cod4, cod5, cod6,
    // FDF
    fdf1, fdf2, fdf3, fdf4, fdf5,
    // PLG
    plg1,
    // RAD
    rad1, rad2, rad3,
    // RCH
    rch1, rch2,
    // SAV
    sav1, sav2, sav3,
    // TRS
    trs1, trs2, trs3, trs4, trs5,
    // IBNB
    ibnb1, ibnb2, ibnb3,
    // CYNO
    cyno1, cyno2,
    // Spécialités
    sal, sh, usar, grimp,
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
    // SR (Secours Routier)
    sr: SkillLevelColor.equipier,
    srCA: SkillLevelColor.chiefOfficer,
    // COD
    cod0: SkillLevelColor.equipier,
    cod1: SkillLevelColor.teamLeader,
    cod2VL: SkillLevelColor.chiefOfficer,
    cod2PL: SkillLevelColor.chiefOfficer,
    cod3: SkillLevelColor.groupLeader,
    cod4: SkillLevelColor.chiefOfficer,
    cod5: SkillLevelColor.groupLeader,
    cod6: SkillLevelColor.specialty,
    // FDF (Feux De Forêt)
    fdf1: SkillLevelColor.equipier,
    fdf2: SkillLevelColor.chiefOfficer,
    fdf3: SkillLevelColor.groupLeader,
    fdf4: SkillLevelColor.columnLeader,
    fdf5: SkillLevelColor.siteLead,
    // PLG (Plongée)
    plg1: SkillLevelColor.specialty,
    // RAD (Risque Radiologique)
    rad1: SkillLevelColor.equipier,
    rad2: SkillLevelColor.teamLeader,
    rad3: SkillLevelColor.chiefOfficer,
    // RCH (Risque Chimique & Biologique)
    rch1: SkillLevelColor.equipier,
    rch2: SkillLevelColor.teamLeader,
    // SAV (Sauvetage Aquatique)
    sav1: SkillLevelColor.equipier,
    sav2: SkillLevelColor.teamLeader,
    sav3: SkillLevelColor.chiefOfficer,
    // TRS (Transmissions)
    trs1: SkillLevelColor.equipier,
    trs2: SkillLevelColor.teamLeader,
    trs3: SkillLevelColor.chiefOfficer,
    trs4: SkillLevelColor.groupLeader,
    trs5: SkillLevelColor.columnLeader,
    // IBNB
    ibnb1: SkillLevelColor.equipier,
    ibnb2: SkillLevelColor.chiefOfficer,
    ibnb3: SkillLevelColor.groupLeader,
    // CYNO (Cynophile)
    cyno1: SkillLevelColor.equipier,
    cyno2: SkillLevelColor.chiefOfficer,
    // Spécialités standalone
    sal: SkillLevelColor.specialty,
    sh: SkillLevelColor.specialty,
    usar: SkillLevelColor.specialty,
    grimp: SkillLevelColor.specialty,
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
      case SkillLevelColor.groupLeader:
        return const Color(0xFFB71C1C); // Rouge profond
      case SkillLevelColor.columnLeader:
        return const Color(0xFF4A148C); // Violet foncé
      case SkillLevelColor.siteLead:
        return const Color(0xFF1A237E); // Bleu marine
      case SkillLevelColor.specialty:
        return const Color(0xFF00695C); // Teal
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
        case SkillLevelColor.apprentice:
          return '';
        case SkillLevelColor.equipier:
          return 'Conducteur';
        case SkillLevelColor.teamLeader:
          return 'Conducteur PL';
        case SkillLevelColor.chiefOfficer:
          return 'Conducteur TT';
        case SkillLevelColor.groupLeader:
          return 'Moniteur / Bat. Pompe';
        case SkillLevelColor.columnLeader:
          return 'Chef de colonne';
        case SkillLevelColor.siteLead:
          return 'Chef de site';
        case SkillLevelColor.specialty:
          return 'Conducteur MEA';
      }
    }

    switch (levelColor) {
      case SkillLevelColor.apprentice:
        return 'Apprenant';
      case SkillLevelColor.equipier:
        return 'Équipier';
      case SkillLevelColor.teamLeader:
        return 'Chef d\'équipe';
      case SkillLevelColor.chiefOfficer:
        return 'Chef d\'agrès';
      case SkillLevelColor.groupLeader:
        return 'Chef de groupe';
      case SkillLevelColor.columnLeader:
        return 'Chef de colonne';
      case SkillLevelColor.siteLead:
        return 'Chef de site';
      case SkillLevelColor.specialty:
        return 'Spécialité';
    }
  }

  /// Icons for each skill category
  static const Map<String, IconData> skillCategoryIcons = {
    'SUAP': Icons.healing_outlined,
    'PPBE': Icons.build,
    'INC': Icons.local_fire_department,
    'SR': Icons.car_crash_sharp,
    'COD': Icons.album,
    'FDF': Icons.forest,
    'PLG': Icons.water,
    'RAD': Icons.warning_amber_rounded,
    'RCH': Icons.science,
    'SAV': Icons.pool,
    'TRS': Icons.campaign,
    'IBNB': Icons.anchor,
    'CYNO': Icons.pets,
    'SAL': Icons.water,
    'SH': Icons.flight,
    'USAR': Icons.search,
    'GRIMP': Icons.terrain,
  };

  /// Skill levels hierarchy: category -> ordered list from lowest to highest
  static const Map<String, List<String>> skillLevels = {
    'SUAP': [suapA, suap, '', suapCA],
    'PPBE': [ppbeA, ppbe, '', ppbeCA],
    'INC': [incA, inc, incCE, incCA],
    'SR': ['', sr, '', srCA],
    // COD : VL → PL → TT-VL → TT-PL → Embarcation → Moniteur → Bat.Pompe → MEA
    'COD': ['', cod0, cod1, cod2VL, cod2PL, '', cod4, cod3, cod5, cod6],
    'FDF': ['', fdf1, '', fdf2, fdf3, fdf4, fdf5],
    'PLG': [plg1],
    'RAD': ['', rad1, rad2, rad3],
    'RCH': ['', rch1, rch2],
    'SAV': ['', sav1, sav2, sav3],
    'TRS': ['', trs1, trs2, trs3, trs4, trs5],
    'IBNB': ['', ibnb1, '', ibnb2, ibnb3],
    'CYNO': ['', cyno1, '', cyno2],
    'SAL': [sal],
    'SH': [sh],
    'USAR': [usar],
    'GRIMP': [grimp],
  };

  /// Catégories dont les compétences sont indépendantes les unes des autres :
  /// cocher un niveau supérieur ne force PAS l'auto-sélection des niveaux inférieurs.
  static const Set<String> standaloneCategories = {
    'COD',
    'PLG',
    'SAL',
    'SH',
    'USAR',
    'GRIMP',
  };

  /// Display order for skill categories
  static const List<String> skillCategoryOrder = [
    'SUAP',
    'PPBE',
    'INC',
    'SR',
    'COD',
    'FDF',
    'RAD',
    'RCH',
    'SAV',
    'PLG',
    'IBNB',
    'CYNO',
    'TRS',
    'SAL',
    'SH',
    'USAR',
    'GRIMP',
  ];

  /// Descriptions des catégories de compétences
  static const Map<String, String> skillCategoryDescriptions = {
    'SUAP': 'Secours d\'Urgence aux Personnes',
    'PPBE': 'Protection des Personnes, des Biens et de l\'Environnement',
    'INC': 'Incendie',
    'SR': 'Secours Routier',
    'COD': 'Conducteur',
    'FDF': 'Feux de Forêts',
    'RAD': 'Risque Radiologique',
    'RCH': 'Risque Chimique & Biologique',
    'SAV': 'Sauveteur Aquatique',
    'PLG': 'Plongée',
    'IBNB': 'Intervention à Bord des Navires et des Bâteaux',
    'CYNO': 'Cynotechnie',
    'TRS': 'Transmission',
    'SAL': 'Scaphandrier Autonome Léger',
    'SH': 'Sauveteur Héliporté',
    'USAR': 'Unité de Sauvetage Appui et Recherche',
    'GRIMP': 'Reconnaissance et d\'Intervention en Milieu périlleux',
  };

  /// Noms courts d'affichage pour les compétences dont la valeur de constante est une phrase
  /// (pour les autres, la valeur de la constante est déjà le nom court)
  static const Map<String, String> skillShortNames = {
    // SUAP
    suapA: 'Apprenti SUAP',
    suapCA: 'CA SUAP',
    // PPBE
    ppbeA: 'Apprenti PPBE',
    ppbeCA: 'CA PPBE',
    // INC
    incA: 'Apprenti INC',
    incCE: 'CE INC',
    incCA: 'CA INC',
    // SR
    srCA: 'CA SR',
  };

  /// Descriptions des compétences individuelles
  static const Map<String, String> skillDescriptions = {
    // SUAP
    suapA: 'Apprenti équipier SUAP',
    suap: 'Equipier SUAP',
    suapCA: 'Chef d\'agrès SUAP',
    // PPBE
    ppbeA: 'Apprenti équipier PPBE',
    ppbe: 'Equipier PPBE',
    ppbeCA: 'Chef d\'agrès PPBE',
    // INC
    incA: 'Apprenti équipier INC',
    inc: 'Equipier INC',
    incCE: 'Chef d\'équipe INC',
    incCA: 'Chef d\'agrès INC',
    // SR
    sr: 'Equipier Secours Routier',
    srCA: 'Chef d\'agrès Secours Routier',
    // COD
    cod0: 'Conducteur Véhicule Léger',
    cod1: 'Conducteur Poids Lourd',
    cod2VL: 'Conducteur Tout-Terrain Véhicule Léger',
    cod2PL: 'Conducteur Tout-Terrain Poids Lourd',
    cod3: 'Moniteur de Conduite Tout-Terrain',
    cod4: 'Conducteur Embarcation',
    cod5: 'Conducteur Bateau Pompe',
    cod6: 'Conducteur MEA',
    // FDF
    fdf1: 'Equipier FDF',
    fdf2: 'Chef d\'agrès FDF',
    fdf3: 'Chef de groupe FDF',
    fdf4: 'Chef de colonne FDF',
    fdf5: 'Chef de site FDF',
    // PLG
    plg1: 'Spécialité Plongée',
    // RAD
    rad1: 'Equipier Risque Radiologique',
    rad2: 'Chef d\'équipe Risque Radiologique',
    rad3: 'Chef d\'agrès Risque Radiologique',
    // RCH
    rch1: 'Equipier Risque Chimique & Biologique',
    rch2: 'Chef d\'équipe Risque Chimique & Biologique',
    // SAV
    sav1: 'Nageur Sauveteur Aquatique',
    sav2: 'Sauveteur Côtier',
    sav3: 'Chef de bord',
    // TRS
    trs1: 'Opérateur PC',
    trs2: 'Opérateur CTA/CODIS',
    trs3: 'Chef de salle',
    trs4: 'Officier transmissions',
    trs5: 'Commandant transmissions',
    // IBNB
    ibnb1: 'Equipier d\'Intervention à Bord des Navires et des Bâteaux',
    ibnb2: 'Chef d\'équipe d\'Intervention à Bord des Navires et des Bâteaux',
    ibnb3: 'Chef de groupe d\'Intervention à Bord des Navires et des Bâteaux',
    // CYNO
    cyno1: 'Conducteur Cynotechnique',
    cyno2: 'Chef d\'unité cynotechnique',
    // Spécialités standalone
    sal: 'Scaphandrier Autonome Léger',
    sh: 'Sauveteur Héliporté',
    usar: 'Unité de Sauvetage Appui et Recherche',
    grimp: 'Reconnaissance et d\'Intervention en Milieu périlleux',
  };

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
    'car_crash_sharp': 'SR',
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

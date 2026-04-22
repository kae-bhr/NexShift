import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/presentation/pages/about_page.dart';
import 'package:nexshift_app/core/presentation/pages/privacy_policy_page.dart';
import 'package:nexshift_app/core/presentation/pages/terms_of_service_page.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/services/push_notification_service.dart';
import 'package:nexshift_app/core/services/local_reminder_service.dart';
import 'package:nexshift_app/features/auth/presentation/pages/login_page.dart';
import 'package:nexshift_app/features/auth/presentation/pages/station_search_page.dart';
import 'package:nexshift_app/features/auth/presentation/pages/welcome_page.dart';
import 'package:nexshift_app/features/settings/presentation/pages/logs_viewer_page.dart';
import 'package:nexshift_app/features/skills/presentation/pages/skills_page.dart';
import 'package:nexshift_app/features/settings/presentation/pages/notification_settings_page.dart';
import 'package:nexshift_app/features/settings/presentation/pages/sync_settings_page.dart';
import 'package:nexshift_app/features/settings/presentation/pages/similar_agents_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/services/maintenance_service.dart';

const String appVersion = '1.0.0';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final user = userNotifier.value;

    return Scaffold(
      appBar: CustomAppBar(
        title: "Paramètres",
        bottomColor: KColors.appNameColor,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section Profil
          _buildSectionHeader(context, 'Profil'),
          _buildProfileCard(context, user),
          const SizedBox(height: 24),

          // Section Préférences
          _buildSectionHeader(context, 'Préférences'),
          _buildPreferencesSection(context),
          const SizedBox(height: 24),

          // Section Données
          _buildSectionHeader(context, 'Données'),
          _buildDataSection(context),
          const SizedBox(height: 24),

          // Section Informations
          _buildSectionHeader(context, 'Informations'),
          _buildInformationsSection(context),
          const SizedBox(height: 24),

          // Footer
          Center(
            child: Text(
              '© NexShift 2025-2026',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, user) {
    if (user == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Aucun utilisateur connecté'),
        ),
      );
    }

    return FutureBuilder(
      future: TeamRepository().getById(user.team, stationId: user.station),
      builder: (context, snapshot) {
        final team = snapshot.data;
        final teamColor = team?.color ?? Colors.grey;

        return Card(
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: teamColor.withOpacity(0.2),
                  child: Text(
                    user.initials,
                    style: TextStyle(
                      color: teamColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  user.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.badge, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Matricule : ${user.id}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.groups, size: 14, color: teamColor),
                        const SizedBox(width: 4),
                        Text('Équipe ${user.team}'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          user.status == KConstants.statusLeader
                              ? Icons.shield_moon_outlined
                              : user.status == KConstants.statusChief
                              ? Icons.verified_user
                              : Icons.person_outline,
                          size: 14,
                          color: user.status == KConstants.statusLeader
                              ? Colors.purple
                              : user.status == KConstants.statusChief
                              ? Colors.orange
                              : Colors.blue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          user.status == KConstants.statusLeader
                              ? 'Chef de centre'
                              : user.status == KConstants.statusChief
                              ? 'Chef de garde'
                              : 'Agent',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('Mes compétences'),
                subtitle: Text('${user.skills.length} compétence(s)'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SkillsPage()),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.people_outline, color: Colors.blue),
                title: const Text('Agents similaires'),
                subtitle: const Text('Découvrez qui vous ressemble le plus'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SimilarAgentsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPreferencesSection(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ValueListenableBuilder(
            valueListenable: isDarkModeNotifier,
            builder: (context, isDarkMode, child) {
              return SwitchListTile(
                secondary: Icon(
                  isDarkMode ? Icons.dark_mode : Icons.light_mode,
                ),
                title: const Text('Mode sombre'),
                subtitle: Text(isDarkMode ? 'Activé' : 'Désactivé'),
                value: isDarkMode,
                onChanged: (value) async {
                  isDarkModeNotifier.value = value;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(KConstants.themeModeKey, value);
                },
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Configurer les notifications push'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            enabled: false,
            leading: const Icon(Icons.language),
            title: const Text('Langue'),
            subtitle: const Text('Français'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.bug_report, color: Colors.orange),
            title: const Text('Logs de débogage'),
            subtitle: const Text('Consulter les logs de l\'application'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogsViewerPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cached),
            title: const Text('Synchronisation'),
            subtitle: const Text('Gérer la synchronisation des données'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SyncSettingsPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('Vider le cache'),
            subtitle: const Text('Libérer de l\'espace'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showClearCacheDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationsSection(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: const Text(appVersion),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Conditions d\'utilisation'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TermsOfServicePage(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Politique de confidentialité'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PrivacyPolicyPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('À propos'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Changer de caserne'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _gestionChangementCaserne(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Colors.red),
            title: const Text(
              'Changer mon mot de passe',
              style: TextStyle(color: Colors.red),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _gestionChangementMotDePasse(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Déconnexion',
              style: TextStyle(color: Colors.red),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _gestionDeconnexion(),
          ),
          const Divider(height: 1, thickness: 2, color: Colors.red),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Supprimer mon compte',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Action irréversible',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.red,
            ),
            onTap: () => _gestionSuppressionCompte(),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Vider le cache',
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: KTextStyle.regularTextStyle.fontSize,
              fontFamily: KTextStyle.regularTextStyle.fontFamily,
              fontWeight: KTextStyle.regularTextStyle.fontWeight,
            ),
          ),
          content: Text(
            'Voulez-vous vider le cache de l\'application ?\n\nCela permettra de libérer de l\'espace de stockage.',
            style: TextStyle(
              color: colorScheme.tertiary,
              fontSize: KTextStyle.descriptionTextStyle.fontSize,
              fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
              fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  // Vider GetStorage
                  final storage = GetStorage();
                  await storage.erase();

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cache vidé avec succès'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erreur : $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Vider'),
            ),
          ],
        );
      },
    );
  }

  /// Gère le changement de caserne pour les utilisateurs multi-affectés
  void _gestionChangementCaserne() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StationSearchPage()),
    );
  }

  void _gestionChangementMotDePasse() {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Mot de passe',
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: KTextStyle.regularTextStyle.fontSize,
              fontFamily: KTextStyle.regularTextStyle.fontFamily,
              fontWeight: KTextStyle.regularTextStyle.fontWeight,
            ),
          ),
          content: Text(
            'Vous êtes sur le point de modifier votre mot de passe.\n\nEn êtes-vous sûr ?',
            style: TextStyle(
              color: colorScheme.tertiary,
              fontSize: KTextStyle.descriptionTextStyle.fontSize,
              fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
              fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('Non'),
            ),
            FilledButton(
              onPressed: () async {
                final SharedPreferences prefs =
                    await SharedPreferences.getInstance();

                // Suppression de l'instance de l'utilisateur stockée
                await UserStorageHelper.clearUser();

                // Suppression de l'instance du token d'authentification stocké
                isUserAuthentifiedNotifier.value = false;
                await prefs.setBool(
                  KConstants.authentifiedKey,
                  isUserAuthentifiedNotifier.value,
                );

                // Retour à la page de connexion en supprimant les pages intermédiaires
                Navigator.pop(context);
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginPage(chgtPw: true),
                  ),
                  (route) => false,
                );
              },
              child: const Text('Oui'),
            ),
          ],
        );
      },
    );
  }

  void _gestionDeconnexion() {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Déconnexion',
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: KTextStyle.regularTextStyle.fontSize,
              fontFamily: KTextStyle.regularTextStyle.fontFamily,
              fontWeight: KTextStyle.regularTextStyle.fontWeight,
            ),
          ),
          content: Text(
            'Vous êtes sur le point de vous déconnecter.\n\nEn êtes-vous sûr ?',
            style: TextStyle(
              color: colorScheme.tertiary,
              fontSize: KTextStyle.descriptionTextStyle.fontSize,
              fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
              fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('Je reste connecté'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final SharedPreferences prefs =
                      await SharedPreferences.getInstance();

                  // Récupérer l'utilisateur avant de le supprimer (pour avoir son ID)
                  final user = userNotifier.value;

                  // Supprimer le token FCM et annuler le rappel quotidien
                  if (user != null) {
                    final pushNotificationService = PushNotificationService();
                    await pushNotificationService.clearDeviceToken(
                      user.id,
                      authUid: user.authUid,
                    );
                    await LocalReminderService().cancelReminder();
                  }

                  // IMPORTANT: Déconnecter Firebase Auth en premier
                  debugPrint('🔴 [LOGOUT] Signing out from Firebase Auth');
                  await FirebaseAuth.instance.signOut();
                  debugPrint('🔴 [LOGOUT] Firebase Auth signed out');

                  // Arrêter l'écoute maintenance SDIS et réinitialiser l'état
                  MaintenanceService().stopListeningForSdis();
                  MaintenanceService().resetSdisState();
                  debugPrint('🔴 [LOGOUT] SDIS maintenance listener stopped');

                  // Suppression de l'instance de l'utilisateur stockée
                  await UserStorageHelper.clearUser();
                  userNotifier.value = null;
                  debugPrint('🔴 [LOGOUT] User notifier cleared');

                  // Vider GetStorage (cache local)
                  final storage = GetStorage();
                  await storage.erase();

                  // Suppression de l'instance du token d'authentification stocké
                  isUserAuthentifiedNotifier.value = false;
                  await prefs.setBool(KConstants.authentifiedKey, false);
                  debugPrint('🔴 [LOGOUT] Auth notifier set to false');

                  // Retour à la page d'accueil en supprimant les pages intermédiaires
                  if (mounted) {
                    Navigator.pop(context);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const WelcomePage()),
                      (route) => false,
                    );
                    debugPrint('🔴 [LOGOUT] Navigated to WelcomePage');
                  }
                } catch (e) {
                  debugPrint('❌ [LOGOUT] Error during logout: $e');
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erreur lors de la déconnexion: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Je me déconnecte'),
            ),
          ],
        );
      },
    );
  }

  void _gestionSuppressionCompte() {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                'Supprimer mon compte',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: KTextStyle.regularTextStyle.fontSize,
                  fontFamily: KTextStyle.regularTextStyle.fontFamily,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            '⚠️ ATTENTION ⚠️\n\nVous êtes sur le point de supprimer définitivement votre compte.\n\nCette action est IRRÉVERSIBLE et entraînera :\n\n• La suppression de votre compte\n• La perte de toutes vos données\n• La perte de vos plannings et disponibilités\n• Vous ne pourrez plus accéder à l\'application\n\nÊtes-vous absolument certain de vouloir continuer ?',
            style: TextStyle(
              color: colorScheme.tertiary,
              fontSize: KTextStyle.descriptionTextStyle.fontSize,
              fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
              fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                _confirmerSuppressionAvecMotDePasse();
              },
              child: const Text('Continuer'),
            ),
          ],
        );
      },
    );
  }

  void _confirmerSuppressionAvecMotDePasse() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Confirmation requise',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: KTextStyle.regularTextStyle.fontSize,
                  fontFamily: KTextStyle.regularTextStyle.fontFamily,
                  fontWeight: KTextStyle.regularTextStyle.fontWeight,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pour des raisons de sécurité, veuillez confirmer votre identité :',
                    style: TextStyle(
                      color: colorScheme.tertiary,
                      fontSize: KTextStyle.descriptionTextStyle.fontSize,
                      fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                      fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Matricule',
                      hintText: 'Votre matricule',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.person),
                    ),
                    keyboardType: TextInputType.text,
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.lock),
                    ),
                    obscureText: true,
                    enabled: !isLoading,
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final matricule = emailController.text.trim();
                          final password = passwordController.text;

                          if (matricule.isEmpty || password.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Veuillez remplir tous les champs',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          // Construire l'email complet avec @nexshift.app
                          final email = '$matricule@nexshift.app';

                          setState(() => isLoading = true);

                          try {
                            // Import Firebase Auth
                            final auth = FirebaseAuth.instance;

                            // Se connecter avec l'email et le mot de passe
                            final userCredential = await auth
                                .signInWithEmailAndPassword(
                                  email: email,
                                  password: password,
                                );

                            final user = userCredential.user;
                            if (user == null) {
                              throw Exception('Utilisateur non trouvé');
                            }

                            debugPrint(
                              '🔥 Suppression du compte utilisateur: $matricule (UID: ${user.uid})',
                            );

                            // Ré-authentifier l'utilisateur (requis pour la suppression)
                            final credential = EmailAuthProvider.credential(
                              email: email,
                              password: password,
                            );
                            await user.reauthenticateWithCredential(credential);

                            // 1. Supprimer le document utilisateur de Firestore AVANT de supprimer le compte Auth
                            // IMPORTANT: Le document Firestore utilise le matricule comme ID, pas l'UID Firebase
                            try {
                              debugPrint(
                                '🗑️ Suppression du document Firestore users/$matricule...',
                              );
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(matricule)
                                  .delete();
                              debugPrint(
                                '✅ Document Firestore users/$matricule supprimé',
                              );
                            } catch (e) {
                              debugPrint(
                                '❌ Erreur lors de la suppression Firestore: $e',
                              );
                              // On continue même si Firestore échoue
                            }

                            // 2. Supprimer le compte Authentication
                            debugPrint(
                              '🗑️ Suppression du compte Authentication...',
                            );
                            await user.delete();
                            debugPrint('✅ Compte Authentication supprimé');

                            // 3. Nettoyer les données locales APRÈS la suppression
                            debugPrint('🧹 Nettoyage des données locales...');
                            final SharedPreferences prefs =
                                await SharedPreferences.getInstance();
                            await UserStorageHelper.clearUser();
                            final storage = GetStorage();
                            await storage.erase();
                            isUserAuthentifiedNotifier.value = false;
                            await prefs.setBool(
                              KConstants.authentifiedKey,
                              false,
                            );
                            debugPrint('✅ Données locales nettoyées');

                            if (mounted) {
                              // Fermer tous les dialogues et retourner à la page d'accueil
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const WelcomePage(),
                                ),
                                (route) => false,
                              );

                              // Afficher un message de confirmation
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Votre compte a été supprimé avec succès',
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 5),
                                ),
                              );
                            }
                          } catch (e) {
                            setState(() => isLoading = false);

                            String errorMessage = 'Une erreur est survenue';

                            if (e.toString().contains('invalid-email')) {
                              errorMessage = 'Adresse email invalide';
                            } else if (e.toString().contains(
                              'user-not-found',
                            )) {
                              errorMessage =
                                  'Aucun compte ne correspond à cette adresse email';
                            } else if (e.toString().contains(
                              'wrong-password',
                            )) {
                              errorMessage = 'Mot de passe incorrect';
                            } else if (e.toString().contains(
                              'too-many-requests',
                            )) {
                              errorMessage =
                                  'Trop de tentatives. Réessayez plus tard';
                            } else if (e.toString().contains(
                              'network-request-failed',
                            )) {
                              errorMessage =
                                  'Erreur réseau. Vérifiez votre connexion';
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(errorMessage),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: const Text('Supprimer définitivement'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

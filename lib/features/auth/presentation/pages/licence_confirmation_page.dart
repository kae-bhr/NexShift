import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/auth_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/repositories/auth_repository.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/services/firebase_auth_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/enter_app_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/password_strength_field_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/snake_bar_widget.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';

/// Page de confirmation pour la création d'un compte via licence
class LicenceConfirmationPage extends StatefulWidget {
  const LicenceConfirmationPage({
    super.key,
    required this.licence,
    required this.auth,
  });

  final String licence;
  final Auth auth;

  @override
  State<LicenceConfirmationPage> createState() =>
      _LicenceConfirmationPageState();
}

class _LicenceConfirmationPageState extends State<LicenceConfirmationPage> {
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _confirmPwController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _pwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: const CustomAppBar(
        title: "Création du mot de passe",
        leading: SizedBox.shrink(),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const HeroWidget(),
                const SizedBox(height: 10),
                _buildWelcomeText(colorScheme),
                const SizedBox(height: 20),
                PasswordStrengthField(
                  controller: _pwController,
                  hintText: 'Mot de passe',
                  isVisible: _isPasswordVisible,
                  onToggle: () =>
                      setState(() => _isPasswordVisible = !_isPasswordVisible),
                  showStrengthBar: true,
                ),
                PasswordStrengthField(
                  controller: _confirmPwController,
                  hintText: 'Confirmez le mot de passe',
                  isVisible: _isConfirmPasswordVisible,
                  onToggle: () => setState(
                    () =>
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                  ),
                  showStrengthBar: false,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _isLoading ? null : _onSavePressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 45),
                    textStyle: textTheme.titleMedium?.copyWith(fontSize: 16),
                  ),
                  child: const Text("Créer mon compte"),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  /// Texte de bienvenue personnalisé
  Widget _buildWelcomeText(ColorScheme colorScheme) {
    return RichText(
      textAlign: TextAlign.justify,
      text: TextSpan(
        style: TextStyle(
          color: colorScheme.tertiary,
          fontSize: KTextStyle.descriptionTextStyle.fontSize,
          fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
        ),
        children: [
          const TextSpan(
            text: 'Bienvenue administrateur de la caserne ',
            style: TextStyle(fontWeight: FontWeight.w300),
          ),
          TextSpan(
            text: widget.auth.station,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: KColors.appNameColor,
            ),
          ),
          const TextSpan(
            text:
                '\n\nVotre licence a été validée pour le matricule ',
            style: TextStyle(fontWeight: FontWeight.w300),
          ),
          TextSpan(
            text: widget.auth.id,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: KColors.appNameColor,
            ),
          ),
          const TextSpan(
            text:
                '.\n\nMerci de bien vouloir insérer deux fois le même mot de passe valide pour créer votre compte administrateur.',
            style: TextStyle(fontWeight: FontWeight.w300),
          ),
        ],
      ),
    );
  }

  void _onSavePressed() async {
    final pw = _pwController.text.trim();
    final confirmPw = _confirmPwController.text.trim();
    final colorScheme = Theme.of(context).colorScheme;

    // Validation des champs
    if (pw.isEmpty || confirmPw.isEmpty) {
      SnakebarWidget.showSnackBar(
        context,
        'Veuillez remplir les deux champs.',
        colorScheme.error,
      );
      return;
    }

    if (pw != confirmPw) {
      _pwController.clear();
      _confirmPwController.clear();
      SnakebarWidget.showSnackBar(
        context,
        'Les mots de passe ne correspondent pas.',
        colorScheme.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Créer la station
      final stationRepo = StationRepository();
      final station = Station(
        id: widget.auth.station,
        name: widget.auth.station,
        notificationWaveDelayMinutes: 30,
      );
      await stationRepo.upsert(station);

      // 2. Créer l'utilisateur admin
      final userRepo = UserRepository();
      final user = User(
        id: widget.auth.id,
        lastName: '', // Sera complété plus tard par l'admin
        firstName: '', // Sera complété plus tard par l'admin
        station: widget.auth.station,
        status: 'active',
        admin: true,
        team: '', // Sera complété plus tard
        skills: [], // Sera complété plus tard
      );
      await userRepo.upsert(user);

      // 3. Créer l'authentification Firebase
      final authService = FirebaseAuthService();
      await authService.createUser(
        matricule: widget.auth.id,
        password: pw,
      );

      // 4. Marquer la licence comme consommée
      final authRepo = AuthRepository();
      final consumedAuth = widget.auth.copyWith(
        consumed: true,
        consumedAt: DateTime.now(),
      );
      await authRepo.updateLicence(consumedAuth);

      // 5. Mettre à jour le mot de passe dans LocalRepository (si utilisé)
      final localRepo = LocalRepository();
      try {
        await localRepo.updatePassword(widget.auth.id, pw);
      } catch (e) {
        // Ignore si LocalRepository n'a pas encore l'utilisateur
      }

      setState(() => _isLoading = false);

      // 6. Rediriger vers l'application
      if (!mounted) return;

      SnakebarWidget.showSnackBar(
        context,
        'Compte créé avec succès ! Bienvenue sur NexShift.',
        colorScheme.primary,
      );

      // Connexion automatique
      EnterApp.build(context, widget.auth.id);
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;

      SnakebarWidget.showSnackBar(
        context,
        'Erreur lors de la création du compte: $e',
        colorScheme.error,
      );
    }
  }
}

import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/widget_tree.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/snake_bar_widget.dart';

/// Page de complétion du profil utilisateur
/// Affichée lorsque firstName ou lastName sont vides
class ProfileCompletionPage extends StatefulWidget {
  const ProfileCompletionPage({
    super.key,
    required this.user,
  });

  final User user;

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Préremplir les champs si déjà définis
    _firstNameController.text = widget.user.firstName;
    _lastNameController.text = widget.user.lastName;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: const CustomAppBar(
        title: "Compléter votre profil",
        leading: SizedBox.shrink(), // Empêcher le retour
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
                TextField(
                  controller: _lastNameController,
                  style: TextStyle(
                    color: colorScheme.tertiary,
                    fontSize: KTextStyle.descriptionTextStyle.fontSize,
                    fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Nom',
                    hintText: 'Votre nom de famille',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _firstNameController,
                  style: TextStyle(
                    color: colorScheme.tertiary,
                    fontSize: KTextStyle.descriptionTextStyle.fontSize,
                    fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Prénom',
                    hintText: 'Votre prénom',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    prefixIcon: const Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _isLoading ? null : _onSavePressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 45),
                    textStyle: textTheme.titleMedium?.copyWith(fontSize: 16),
                  ),
                  child: const Text("Continuer"),
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
            text: 'Bienvenue sur NexShift !\n\n',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const TextSpan(
            text: 'Pour finaliser votre inscription, merci de renseigner vos ',
            style: TextStyle(fontWeight: FontWeight.w300),
          ),
          const TextSpan(
            text: 'nom et prénom',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(
            text: '.\n\n',
            style: TextStyle(fontWeight: FontWeight.w300),
          ),
          const TextSpan(
            text: 'Matricule : ',
            style: TextStyle(fontWeight: FontWeight.w300),
          ),
          TextSpan(
            text: widget.user.id,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: KColors.appNameColor,
            ),
          ),
        ],
      ),
    );
  }

  void _onSavePressed() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final colorScheme = Theme.of(context).colorScheme;

    // Validation
    if (firstName.isEmpty || lastName.isEmpty) {
      SnakebarWidget.showSnackBar(
        context,
        'Veuillez renseigner votre nom et prénom.',
        colorScheme.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Mettre à jour l'utilisateur
      final userRepo = UserRepository();
      final updatedUser = widget.user.copyWith(
        firstName: firstName,
        lastName: lastName,
      );
      await userRepo.upsert(updatedUser);

      // Mettre à jour les notifiers locaux
      userNotifier.value = updatedUser;
      await UserStorageHelper.saveUser(updatedUser);

      setState(() => _isLoading = false);

      if (!mounted) return;

      // Rediriger vers WidgetTree (la structure principale de l'app)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WidgetTree()),
        (route) => false, // Supprimer toutes les routes précédentes
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;

      SnakebarWidget.showSnackBar(
        context,
        'Erreur lors de la mise à jour du profil: $e',
        colorScheme.error,
      );
    }
  }
}

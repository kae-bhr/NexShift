import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/enter_app_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/password_strength_field_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/snake_bar_widget.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';

class ConfirmationPage extends StatefulWidget {
  const ConfirmationPage({super.key, required this.id});

  final String id;

  @override
  State<ConfirmationPage> createState() => _ConfirmationPageState();
}

class _ConfirmationPageState extends State<ConfirmationPage> {
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _confirmPwController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  String? _firstName;
  String? _lastName;
  bool _isLoading = true;

  @override
  void initState() {
    initUser();
    super.initState();
  }

  void initUser() async {
    try {
      final repo = LocalRepository();
      final User user = await repo.getUserProfile(widget.id);
      setState(() {
        _firstName = user.firstName;
        _lastName = user.lastName;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _firstName = "";
        _lastName = "";
        _isLoading = false;
      });

      SnakebarWidget.showSnackBar(
        context,
        'Problème de gestion de licence.',
        Theme.of(context).colorScheme.error,
      );
    }
  }

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
      appBar: CustomAppBar(
        title: "Création du mot de passe",
        leading: const SizedBox.shrink(),
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
                  onPressed: _onSavePressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 45),
                    textStyle: textTheme.titleMedium?.copyWith(fontSize: 16),
                  ),
                  child: const Text("Sauvegarder le mot de passe"),
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
            text: 'Bienvenue ',
            style: TextStyle(fontWeight: FontWeight.w300),
          ),
          TextSpan(
            text: _firstName ?? '',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: KColors.appNameColor,
            ),
          ),
          const TextSpan(
            text: ' ',
            style: TextStyle(fontWeight: FontWeight.w300),
          ),
          TextSpan(
            text: _lastName ?? '',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: KColors.appNameColor,
            ),
          ),
          const TextSpan(
            text:
                '\n\nMerci de bien vouloir insérer deux fois le même mot de passe valide pour finaliser votre inscription.',
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

    EnterApp.build(context, widget.id);

    final repo = LocalRepository();
    await repo.updatePassword(widget.id, confirmPw);
  }
}

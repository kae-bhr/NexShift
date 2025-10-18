import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/app/presentation/pages/home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isPasswordVisible = false;
  Icon passwordIcon = Icon(Icons.visibility_off);
  TextEditingController controllerId = TextEditingController();
  TextEditingController controllerPw = TextEditingController();

  // TODO : A supprimer lorsque l'authentification sera opérationnelle
  String confirmedId = '8513';
  String confirmedPw = '1234';

  @override
  void dispose() {
    controllerId.dispose();
    controllerPw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Connexion", style: KTextStyle.regularTextStyleLightMode),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            HeroWidget(),
            Text(
              "Insérez vos identifiants de connexion",
              style: KTextStyle.descriptionTextStyleLightMode,
            ),
            SizedBox(height: 10.0),
            TextField(
              controller: controllerId,
              style: KTextStyle.descriptionTextStyleLightMode,
              decoration: InputDecoration(
                hintText: 'Matricule',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15.0),
                ),
                prefixIcon: const Icon(Icons.person, color: Colors.grey),
              ),
              onEditingComplete: () {
                setState(() {});
              },
            ),
            SizedBox(height: 10.0),
            TextField(
              controller: controllerPw,
              style: KTextStyle.descriptionTextStyleLightMode,
              obscureText: isPasswordVisible ? false : true,
              decoration: InputDecoration(
                hintText: 'Mot de passe',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15.0),
                ),
                prefixIcon: const Icon(Icons.lock, color: Colors.grey),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      isPasswordVisible = !isPasswordVisible;
                      if (isPasswordVisible) {
                        passwordIcon = const Icon(
                          Icons.visibility,
                          color: Colors.grey,
                        );
                      } else {
                        passwordIcon = const Icon(
                          Icons.visibility_off,
                          color: Colors.grey,
                        );
                      }
                    });
                  },
                  icon: passwordIcon,
                ),
              ),
              onEditingComplete: () {
                setState(() {});
              },
            ),
            SizedBox(height: 10.0),
            FilledButton(
              onPressed: () {
                onLoginPressed();
              },
              style: FilledButton.styleFrom(
                minimumSize: Size(double.infinity, 40.0),
              ),
              child: Text("Se connecter", style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  void onLoginPressed() {
    if (controllerId.text == confirmedId && controllerPw.text == confirmedPw) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) {
            return HomePage();
          },
        ),
      );
    } else {
      controllerPw.text = '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mot de passe erroné',
            style: KTextStyle.descriptionTextStyleLightMode,
          ),
        ),
      );
    }
  }
}

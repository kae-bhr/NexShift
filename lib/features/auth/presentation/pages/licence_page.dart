import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/app/presentation/pages/home_page.dart';

class LicencePage extends StatefulWidget {
  const LicencePage({super.key});

  @override
  State<LicencePage> createState() => _LicencePageState();
}

class _LicencePageState extends State<LicencePage> {
  bool isLicenceVisible = false;
  Icon licenceIcon = Icon(Icons.visibility_off);
  TextEditingController controllerLicence = TextEditingController();

  // TODO : A supprimer lorsque l'authentification sera opérationnelle
  String confirmedLicence = 'toto';
  String alreadyUsedLicence = 'titi';

  @override
  void dispose() {
    controllerLicence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Licence", style: KTextStyle.regularTextStyleLightMode),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            HeroWidget(),
            Text(
              "Insérez votre licence",
              style: KTextStyle.descriptionTextStyleLightMode,
            ),
            SizedBox(height: 10.0),
            TextField(
              controller: controllerLicence,
              style: KTextStyle.descriptionTextStyleLightMode,
              obscureText: isLicenceVisible ? false : true,
              decoration: InputDecoration(
                hintText: 'Licence',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15.0),
                ),
                prefixIcon: const Icon(
                  Icons.shield_rounded,
                  color: Colors.grey,
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      isLicenceVisible = !isLicenceVisible;
                      if (isLicenceVisible) {
                        licenceIcon = const Icon(
                          Icons.visibility,
                          color: Colors.grey,
                        );
                      } else {
                        licenceIcon = const Icon(
                          Icons.visibility_off,
                          color: Colors.grey,
                        );
                      }
                    });
                  },
                  icon: licenceIcon,
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
              child: Text("Se connecter"),
            ),
          ],
        ),
      ),
    );
  }

  void onLoginPressed() {
    if (controllerLicence.text == confirmedLicence) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) {
            return HomePage();
          },
        ),
      );
    } else if (controllerLicence.text == alreadyUsedLicence) {
      controllerLicence.text = '';
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(
              'Licence déjà utilisée',
              style: KTextStyle.regularTextStyleLightMode,
            ),
            content: Text(
              'Merci de contacter votre administrateur de licences.',
              style: KTextStyle.descriptionTextStyleLightMode,
            ),
          );
        },
      );
    } else {
      controllerLicence.text = '';
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(
              'Licence invalide',
              style: KTextStyle.regularTextStyleLightMode,
            ),
            content: RichText(
              textAlign: TextAlign.justify,
              text: TextSpan(
                style: TextStyle(color: Colors.black, fontSize: 36),
                children: [
                  TextSpan(
                    text:
                        'Merci de vérifier votre licence ou de vous en procurer une sur le site : ',
                    style: KTextStyle.descriptionTextStyleLightMode,
                  ),
                  TextSpan(
                    // TODO : A remplacer par le site web de gestion de licences
                    text: 'https://bhr.com/NexShift/licences',
                    style: TextStyle(
                      color: Colors.lightBlue,
                      fontSize: 14,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }
}

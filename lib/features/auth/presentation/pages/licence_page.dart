import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';

class LicencePage extends StatefulWidget {
  const LicencePage({super.key});

  @override
  State<LicencePage> createState() => _LicencePageState();
}

class _LicencePageState extends State<LicencePage> {
  bool isLicenceVisible = false;
  Icon licenceIcon = Icon(Icons.visibility_off);
  TextEditingController controllerLicence = TextEditingController();

  @override
  void dispose() {
    controllerLicence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: "Licence"),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              HeroWidget(),
              Text(
                "Insérez votre licence",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontSize: KTextStyle.descriptionTextStyle.fontSize,
                  fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                  fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
                ),
              ),
              SizedBox(height: 10.0),
              TextField(
                controller: controllerLicence,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontSize: KTextStyle.descriptionTextStyle.fontSize,
                  fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                  fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
                ),
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
      ),
    );
  }

  void onLoginPressed() async {
    // TODO : Implémenter la validation de licence via Firebase/Firestore
    // La fonctionnalité de licence a été désactivée temporairement
    // pendant la migration vers Firebase
    controllerLicence.text = '';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Fonctionnalité désactivée',
            style: TextStyle(
              color: Theme.of(context).colorScheme.tertiary,
              fontSize: KTextStyle.regularTextStyle.fontSize,
              fontFamily: KTextStyle.regularTextStyle.fontFamily,
              fontWeight: KTextStyle.regularTextStyle.fontWeight,
            ),
          ),
          content: Text(
            'La validation de licence sera réimplémentée dans une prochaine version.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.tertiary,
              fontSize: KTextStyle.descriptionTextStyle.fontSize,
              fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
              fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

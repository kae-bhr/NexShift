import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/auth/presentation/pages/licence_page.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: CustomAppBar(title: "", bottomColor: null),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(child: HeroWidget()),
              SizedBox(height: 20.0),
              RichText(
                textAlign: TextAlign.justify,
                text: TextSpan(
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontSize: KTextStyle.descriptionTextStyle.fontSize,
                    fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                  ),
                  children: [
                    TextSpan(
                      text: 'NexShift ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text:
                          'est une application permettant de facilier la gestion des astreintes pour tout service en ayant le besoin.\n\n',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    WidgetSpan(
                      child: Icon(Icons.person, color: KColors.appNameColor),
                    ),
                    TextSpan(
                      text: '\nPour un agent, l\'application permet de ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      text: 'visualiser ses prochaines astreintes ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text: 'et de ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      text: 'proposer des créneaux ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text:
                          'de remplacements alertant automatiquement les personnes par ordre de priorité.\n\n',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    WidgetSpan(
                      child: Icon(Icons.group, color: KColors.appNameColor),
                    ),
                    TextSpan(
                      text:
                          '\nPour un chef d\'équipe, l\'application permet d\'être ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      text: 'notifié de chaque remplacement ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text: 'à effectuer avant une astreinte de son équipe, ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      text: 'visualiser l\'effectif ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text: 'et ses ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      text: 'compétences ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text:
                          'ainsi que proposer des créneaux ouverts à l\'ensemble du groupe en fonction de leurs compétences.\n\n',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    WidgetSpan(
                      child: Icon(Icons.groups, color: KColors.appNameColor),
                    ),
                    TextSpan(
                      text:
                          '\nPour un chef de centre, l\'application permet de définir les ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      text: 'plannings d\'astreintes',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text: ', définir les ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      text: 'compétences ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text: ' et ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      text: 'équipes ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text: 'des agents.\n\n',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    WidgetSpan(
                      child: Icon(
                        Icons.euro_rounded,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text:
                          '\nL\'application est utilisable sous condition d\'obtention d\'une ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      text: 'licence nominative annuellement renouvelable ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: KColors.appNameColor,
                      ),
                    ),
                    TextSpan(
                      text:
                          'pour chaque utilisateur.\nPour obtenir d\'avantage d\'informations concernant la gestion ou l\'acquisition de licences, merci de consulter le site Web suivant : ',
                      style: TextStyle(fontWeight: FontWeight.w300),
                    ),
                    TextSpan(
                      // TODO : A remplacer par le site web de gestion de licences
                      text: 'https://bhr.com/NexShift/licences',
                      style: TextStyle(color: Colors.lightBlue),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20.0),
              FilledButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) {
                        return LicencePage();
                      },
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  minimumSize: Size(double.infinity, 40.0),
                ),
                child: Text("Entrer ma licence"),
              ),
              SizedBox(height: 50.0),
            ],
          ),
        ),
      ),
    );
  }
}

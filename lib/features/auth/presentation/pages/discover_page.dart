import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/auth/presentation/pages/licence_page.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              HeroWidget(),
              RichText(
                textAlign: TextAlign.justify,
                text: TextSpan(
                  style: TextStyle(color: Colors.black, fontSize: 36),
                  children: [
                    TextSpan(
                      text: 'NexShift ',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text:
                          'est une application permettant de facilier la gestion des astreintes pour tout service en ayant le besoin.\n',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    WidgetSpan(
                      child: Icon(Icons.person, color: KColors.appNameColor),
                    ),
                    TextSpan(
                      text: '\nPour un agent, l\'application permet de ',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'visualiser ses prochaines astreintes ',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'et de ',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'proposer des créneaux ',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text:
                          'de remplacements alertant automatiquement les personnes par ordre de priorité.\n',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    WidgetSpan(
                      child: Icon(Icons.group, color: KColors.appNameColor),
                    ),
                    TextSpan(
                      text:
                          '\nPour un chef d\'équipe, l\'application permet d\'être ',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'notifié de chaque remplacement ',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'à effectuer avant une astreinte de son équipe, ',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'visualiser l\'effectif ',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'et ses ',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'compétences ',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text:
                          'ainsi que proposer des créneaux ouverts à l\'ensemble du groupe en fonction de leurs compétences.\n',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    WidgetSpan(
                      child: Icon(Icons.groups, color: KColors.appNameColor),
                    ),
                    TextSpan(
                      text:
                          '\nPour un chef de centre, l\'application permet de définir les ',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'plannings d\'astreintes',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text: ', définir les ',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'compétences ',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text: ' et ',
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'équipes ',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'des agents.\n\n',
                      style: KTextStyle.descriptionTextStyleLightMode,
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
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                    TextSpan(
                      text: 'licence nominative annuellement renouvelable ',
                      style: KTextStyle.descriptionBoldTextStyleLightMode,
                    ),
                    TextSpan(
                      text:
                          'pour chaque utilisateur.\nPour obtenir d\'avantage d\'informations concernant la gestion ou l\'acquisition de licences, merci de consulter le site Web suivant : ',
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

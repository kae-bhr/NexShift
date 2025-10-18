import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "À propos de NexShift",
          style: KTextStyle.regularTextStyleLightMode,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            HeroWidget(),
            Text(
              "blablablablablablablablablablablabla blablablablablablablablabla blablablablablablablablabla\nLicences : blablablablablabla",
              textAlign: TextAlign.justify,
              style: KTextStyle.descriptionTextStyleLightMode,
            ),
          ],
        ),
      ),
    );
  }
}

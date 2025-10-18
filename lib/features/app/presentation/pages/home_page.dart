import 'package:flutter/material.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/app/presentation/pages/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text("NexShift", style: KTextStyle.regularBoldTextStyleLightMode),
            Image(
              image: ResizeImage(
                AssetImage("assets/images/logo.png"),
                width: 40,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) {
                    return SettingsPage();
                  },
                ),
              );
            },
            icon: Icon(Icons.settings),
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              child: Text(
                'Options',
                style: KTextStyle.regularTextStyleLightMode,
              ),
            ),
            Column(
              children: [
                TextButton(
                  onPressed: () {},
                  child: ListTile(
                    minTileHeight: 0.0,
                    leading: Icon(Icons.whatshot),
                    title: Text(
                      "Mes compétences",
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: ListTile(
                    minTileHeight: 0.0,
                    leading: Icon(Icons.groups),
                    title: Text(
                      "Mon équipe",
                      style: KTextStyle.descriptionTextStyleLightMode,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Padding(padding: const EdgeInsets.all(20.0), child: Container()),
      bottomNavigationBar: NavigationBar(
        destinations: [
          NavigationDestination(icon: Icon(Icons.person), label: 'Accueil'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Planning',
          ),
        ],
        onDestinationSelected: (int destinationSelected) {},
        selectedIndex: 0,
      ),
    );
  }
}

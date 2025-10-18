import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexshift_app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const NexShift());
}

class NexShift extends StatelessWidget {
  const NexShift({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        platform: TargetPlatform.iOS,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 211, 50, 50),
          brightness: Brightness.light,
        ),
      ),
      home: App(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/app_services.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  runApp(RecorderApp(services: services));
}

class RecorderApp extends StatelessWidget {
  const RecorderApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D. Recorder Lab',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: HomePage(services: services),
    );
  }
}

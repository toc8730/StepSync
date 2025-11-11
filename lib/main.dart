import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme_controller.dart';
import 'pages/welcome_page.dart';
import 'services/push_notifications.dart';

// Your firebase_options.dart is inside /lib/pages in this project.
import 'firebase_options.dart';

// Start screen — change if you want a different entry.

void main() {
  // Keep ensureInitialized and runApp in the SAME zone.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await PushNotifications.init();

    runApp(const MyApp());
  }, (error, stack) {
    // Optional: send errors to your logger/crash reporter
    // debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (_, __) => MaterialApp(
        title: 'My App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeController.instance.mode,
        home: const WelcomePage(),
      ),
    );
  }
}

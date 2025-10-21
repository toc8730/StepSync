import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'pages/homepage.dart';
import 'pages/create_account_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_background.dart';          // <-- moved here (not in pages/)
import 'services/push_notifications.dart';
import 'pages/login_page.dart';
// Optional: if you used `flutterfire configure`, prefer:
// import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch any init-time crashes and still render a screen
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };

  runZonedGuarded(() async {
    String? initError;

    try {
      // If you have firebase_options.dart, use:
      // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await Firebase.initializeApp();

      // Register the background handler AFTER Firebase is ready
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Init local + foreground notifications and FCM listeners
      await PushNotifications.init();
    } catch (e, st) {
      initError = e.toString();
      debugPrint('Init error: $e\n$st');
    }

    runApp(MyApp(initError: initError));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.initError});
  final String? initError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: initError == null
          ? const LoginPage()
          : InitErrorScreen(error: initError!),
    );
  }
}

class InitErrorScreen extends StatelessWidget {
  const InitErrorScreen({super.key, required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Initialization error',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
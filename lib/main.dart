import 'dart:async';
import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'pages/homepage.dart';
import 'pages/create_account_page.dart';
import 'package:firebase_core/firebase_core.dart';

// Your firebase_options.dart is inside /lib/pages in this project.
import 'firebase_options.dart';

// Start screen — change if you want a different entry.
import 'pages/login_page.dart';

void main() {
  // Keep ensureInitialized and runApp in the SAME zone.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

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
    return MaterialApp(
      title: 'My App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}
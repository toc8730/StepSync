import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'pages/notifications.dart'; // Add this import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await initNotifications(); // Initialize notifications before app starts
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}

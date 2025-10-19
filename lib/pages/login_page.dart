import 'package:flutter/material.dart';
import 'create_account_page.dart';
import 'homepage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final String apiUrl = "http://127.0.0.1:5000/login"; // For emulator

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login Page')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Username field
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Username',
                  hintText: 'Enter your username',
                ),
              ),
              const SizedBox(height: 20),

              // Password field
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Password',
                  hintText: 'Enter your password',
                ),
              ),
              const SizedBox(height: 30),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Log In button
                  ElevatedButton(
                    onPressed: () {
                      final username = _usernameController.text.trim();
                      final password = _passwordController.text.trim();

                      if (username.isEmpty || password.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Both username and password are required!'),
                          ),
                        );
                        return;
                      }

                      http.post(
                        Uri.parse(apiUrl),
                        headers: {'Content-Type': 'application/json'},
                        body: json.encode({'username': username, 'password': password}),
                      ).then((res){
                        if (res.statusCode == 200) {
                          final data = json.decode(res.body);

                          // Navigate to HomePage and clear fields on return
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HomePage(username: username, token: data['token']),
                            ),
                          ).then((_) {
                            _usernameController.clear();
                            _passwordController.clear();
                          });
                          
                        }
                        else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(res.body),
                            ),
                          );
                        }
                      });
                    },
                    child: const Text('Log In'),
                  ),

                  // Create Account button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreateAccountPage(),
                        ),
                      );
                    },
                    child: const Text('Create Account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

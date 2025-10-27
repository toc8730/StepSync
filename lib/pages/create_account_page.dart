import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final String apiUrl = "http://127.0.0.1:5000/register"; // For emulator

  final bool passwordRequirements = false; // for testing

  // api call to register user
  Future<http.Response> addUser(String username, String password) async {
    return http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'username': username, 'password': password, 'account_type': _accountType}),
    );
  }

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String _accountType = 'Parent';
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Username',
                  hintText: 'Enter username',
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Password',
                  hintText: 'Enter password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Confirm Password',
                  hintText: 'Re-enter password',
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Select Account Type:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Radio<String>(
                    value: 'Parent',
                    groupValue: _accountType,
                    onChanged: (value) {
                      setState(() {
                        _accountType = value!;
                      });
                    },
                  ),
                  const Text('Parent'),
                  const SizedBox(width: 20),
                  Radio<String>(
                    value: 'Child',
                    groupValue: _accountType,
                    onChanged: (value) {
                      setState(() {
                        _accountType = value!;
                      });
                    },
                  ),
                  const Text('Child'),
                ],
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  final username = _usernameController.text.trim();
                  final password = _passwordController.text.trim();
                  final confirm = _confirmController.text.trim();

                  if (username.isEmpty || password.isEmpty || confirm.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All fields are required!')),
                    );
                    return;
                  }

                  final passwordPattern =
                      r'^(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$%^&*]).{8,}$';
                  final regExp = RegExp(passwordPattern);
                  if (!regExp.hasMatch(password) && passwordRequirements) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Password must be 8+ chars, include uppercase, number, and special char',
                        ),
                      ),
                    );
                    return;
                  }

                  if (password != confirm) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passwords do not match!')),
                    );
                    return;
                  }
                  
                  addUser(username, password).then((res){ 
                    String body = res.body;
                    if (res.statusCode != 200) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(body)),
                      );
                      return;
                    }
                  }); //try to register the user, return if http status failed
                  

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Account created successfully as $_accountType!',
                      ),
                    ),
                  );

                  Navigator.pop(context);
                },
                child: const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

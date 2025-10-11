import 'package:flutter/material.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  // 👇 New variable to track account type
  String _accountType = 'Parent'; // Default selection

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          // ✅ Prevents overflow on small screens
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Username
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Username',
                  hintText: 'Enter username',
                ),
              ),
              const SizedBox(height: 20),

              // Password
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Password',
                  hintText: 'Enter password',
                ),
              ),
              const SizedBox(height: 20),

              // Confirm password
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

              // 👇 New radio button section
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

              // Create Account button
              ElevatedButton(
                onPressed: () {
                  final username = _usernameController.text.trim();
                  final password = _passwordController.text.trim();
                  final confirm = _confirmController.text.trim();

                  // Check empty fields
                  if (username.isEmpty || password.isEmpty || confirm.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All fields are required!')),
                    );
                    return;
                  }

                  // Password rules
                  final passwordPattern =
                      r'^(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$%^&*]).{8,}$';
                  final regExp = RegExp(passwordPattern);
                  if (!regExp.hasMatch(password)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Password must be 8+ chars, include uppercase, number, and special char',
                        ),
                      ),
                    );
                    return;
                  }

                  // Confirm password match
                  if (password != confirm) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passwords do not match!')),
                    );
                    return;
                  }

                  // ✅ Success message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Account created successfully as $_accountType!',
                      ),
                    ),
                  );

                  // Go back to login
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

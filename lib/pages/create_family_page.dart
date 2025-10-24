import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CreateFamilyPage extends StatefulWidget {
  const CreateFamilyPage({super.key});

  @override
  State<CreateFamilyPage> createState() => _CreateFamilyPageState();
}

class _CreateFamilyPageState extends State<CreateFamilyPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _passwordVisible = false;

  final _storage = const FlutterSecureStorage(); // for JWT token

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _nameValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Family name is required';
    if (s.length > 16) return 'Max 16 characters';
    return null;
  }

  final RegExp _hasLetter = RegExp(r'[A-Za-z]');
  final RegExp _hasDigit = RegExp(r'\d');

  String? _passwordValidator(String? v) {
    final s = (v ?? '');
    if (s.isEmpty) return 'Password is required';
    if (s.length < 8) return 'At least 8 characters';
    if (s.length > 20) return 'Max 20 characters';
    if (!_hasLetter.hasMatch(s) || !_hasDigit.hasMatch(s)) {
      return 'Include letters and numbers';
    }
    return null;
  }

  String? _confirmValidator(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm password';
    if (v != _passwordCtrl.text) return 'Passwords do not match';
    return null;
  }

  String _generateFamilyId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final code = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'FAM-$code';
  }

  Future<void> _createFamily() async {
  print('Create button tapped');

  if (!_formKey.currentState!.validate()) {
    print('Validation failed');
    return;
  }

  final familyId = _generateFamilyId();
  final token = await _storage.read(key: 'jwt_token');
  print('Token: $token');

  if (token == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Missing token. Please log in again.')),
    );
    return;
  }

  print('Sending request to backend...');
  final response = await http.post(
    Uri.parse('http://127.0.0.1:5000/family/create'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({
      'name': _nameCtrl.text.trim(),
      'password': _passwordCtrl.text,
      'family_id': familyId,
    }),
  );

  print('Response status: ${response.statusCode}');
  print('Response body: ${response.body}');

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final createdFamilyId = data['family_id'];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Family Created'),
        content: Text('Your Family ID is: $createdFamilyId'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } else {
    final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $error')),
    );
  }
}
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Family')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Family Name',
                    border: OutlineInputBorder(),
                    helperText: '1–16 characters',
                  ),
                  validator: _nameValidator,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: !_passwordVisible,
                  decoration: InputDecoration(
                    labelText: 'Family Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off),
                      tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                      onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                    ),
                    helperText: '8–20 chars, include letters and numbers',
                  ),
                  validator: _passwordValidator,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(),
                  ),
                  validator: _confirmValidator,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _createFamily,
                        icon: const Icon(Icons.check),
                        label: const Text('Create'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
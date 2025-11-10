import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:my_app/config/backend_config.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

enum AccountType { parent, child }

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _confirm  = TextEditingController();

  bool _showPass = false;
  AccountType _type = AccountType.parent;

  static const _registerUrl = '${BackendConfig.baseUrl}/register';

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final u = _username.text.trim();
    final d = _displayName.text.trim();
    final p = _password.text;
    final c = _confirm.text;

    if (u.isEmpty) {
      _snack('Username required');
      return;
    }
    if (d.isEmpty) {
      _snack('Display name required.');
      return;
    }
    if (p.length < 8 || p.length > 20) {
      _snack('Password must be 8–20 characters.');
      return;
    }
    if (p != c) {
      _snack('Passwords do not match.');
      return;
    }

    final payload = {
      'username': u,
      'password': p,
      'display_name': d,
      // IMPORTANT: send the exact key Flask expects
      'type': _type == AccountType.child ? 'child' : 'parent',
    };

    try {
      final res = await http.post(
        Uri.parse(_registerUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        _snack('Account created. Signing you in…');
        final result = CreateAccountResult(
          username: u,
          password: p,
          role: _type == AccountType.child ? 'child' : 'parent',
        );
        Navigator.of(context).pop(result);
      } else {
        final msg = _safeError(res.body) ?? 'Create failed (${res.statusCode})';
        _snack(msg);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Network error: $e');
    }
  }

  String? _safeError(String body) {
    try {
      final m = json.decode(body);
      if (m is Map && m['error'] is String) return m['error'] as String;
    } catch (_) {}
    return null;
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _displayName,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_showPass,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showPass ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Select Account Type:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                ChoiceChip(
                  selected: _type == AccountType.parent,
                  label: const Text('Parent'),
                  onSelected: (_) => setState(() => _type = AccountType.parent),
                ),
                ChoiceChip(
                  selected: _type == AccountType.child,
                  label: const Text('Child'),
                  onSelected: (_) => setState(() => _type = AccountType.child),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: FilledButton(
                onPressed: () => _create(),
                child: const Text('Create Account'),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class CreateAccountResult {
  const CreateAccountResult({
    required this.username,
    required this.password,
    required this.role,
  });

  final String username;
  final String password;
  final String role;
}

import 'dart:math';
import 'package:flutter/material.dart';

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

  // Password visibility: DEFAULT = hidden (viewing OFF)
  bool _passwordVisible = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // Name: 1..16
  String? _nameValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Family name is required';
    if (s.length > 16) return 'Max 16 characters';
    return null;
  }

  // Password rules: 8..20, letters+numbers
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
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0,1,O,I
    final rnd = Random.secure();
    final code = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'FAM-$code';
  }

  Future<void> _createFamily() async {
    if (!_formKey.currentState!.validate()) return;

    final familyId = _generateFamilyId();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Family Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${_nameCtrl.text.trim()}'),
            const SizedBox(height: 8),
            Text('Family ID: $familyId', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Share this ID with family members so they can join.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );

    if (mounted) Navigator.pop(context);
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
                  obscureText: !_passwordVisible, // hidden by default
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
                // Confirm: always obscured (no toggle)
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
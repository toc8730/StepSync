import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/config/google_oauth_config.dart';
import 'package:my_app/data/globals.dart';
import 'package:my_app/services/preferences_service.dart';
import 'package:my_app/theme_controller.dart';
import 'child_home_page.dart';
import 'create_account_page.dart';
import 'homepage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late final GoogleSignIn _googleSignIn;

  bool _obscure = true;
  bool _canSignIn = false;
  bool _googleLoading = false;

  final String apiUrl = "http://127.0.0.1:5000/login";
  final String _googleLoginUrl = "http://127.0.0.1:5000/login/google";

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_refreshCanSignIn);
    _passwordController.addListener(_refreshCanSignIn);
    _googleSignIn = GoogleSignIn(
      scopes: const ['email'],
      clientId: GoogleOAuthConfig.platformClientId,
      serverClientId: GoogleOAuthConfig.serverClientId,
    );
  }

  void _refreshCanSignIn() {
    final can = _usernameController.text.trim().isNotEmpty &&
        _passwordController.text.trim().isNotEmpty;
    if (can != _canSignIn) setState(() => _canSignIn = can);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _navigateToCreateAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateAccountPage()),
    );
    _usernameController.clear();
    _passwordController.clear();
    _refreshCanSignIn();
  }

  Future<void> _signIn() async {
    if (!_canSignIn) {
      _showSnack('Enter your username and password.');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': _usernameController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        await _handleAuthSuccess(data, fallbackUsername: _usernameController.text.trim());
      } else {
        final Map body = json.decode(response.body);
        final error = body['error'] ?? 'Login failed';
        _showSnack('Error: $error');
      }
    } catch (e) {
      _showSnack('Network error: $e');
    }
  }

  Future<void> _signInWithGoogle() async {
    final configError = GoogleOAuthConfig.configurationHint();
    if (configError != null) {
      _showSnack('Google sign-in unavailable: $configError (see README).');
      return;
    }

    setState(() => _googleLoading = true);
    try {
      final account = await _triggerPlatformSignIn();
      if (account == null) {
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        final message = kIsWeb
            ? 'Google did not return an ID token. Make sure pop-ups were allowed and try again.'
            : 'Unable to retrieve Google token.';
        _showSnack(message);
        return;
      }
      await _submitGoogleToken(idToken, fallbackUsername: account.email);
    } catch (e) {
      _showSnack('Google sign-in error: $e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _submitGoogleToken(String idToken, {required String fallbackUsername, String? preferredRole}) async {
    final payload = <String, String>{
      'id_token': idToken,
      if (preferredRole != null) 'preferred_role': preferredRole,
    };
    final response = await http.post(
      Uri.parse(_googleLoginUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(payload),
    );
    Map<String, dynamic>? body;
    try {
      body = json.decode(response.body) as Map<String, dynamic>?;
    } catch (_) {}

    if (response.statusCode == 200) {
      if (!mounted) return;
      await _handleAuthSuccess(body ?? const {}, fallbackUsername: fallbackUsername);
      return;
    }

    final needsRole = response.statusCode == 412 && (body?['needs_role'] == true || body?['error'] == 'role_required');
    if (needsRole) {
      final role = await _promptGoogleRole();
      if (role == null) {
        _showSnack('Google sign-in cancelled.');
        return;
      }
      await _submitGoogleToken(idToken, fallbackUsername: fallbackUsername, preferredRole: role);
      return;
    }

    final error = body?['message'] ?? body?['error'] ?? 'Google login failed';
    _showSnack('Error: $error');
  }

  Future<GoogleSignInAccount?> _triggerPlatformSignIn() async {
    if (kIsWeb) {
      final silent = await _googleSignIn.signInSilently();
      if (silent != null) return silent;
      final legacy = await _googleSignIn.signIn();
      if (legacy == null) return null;
      // After the legacy flow completes, GIS now knows the user; retry silently to capture the ID token.
      return _googleSignIn.signInSilently();
    }
    return _googleSignIn.signIn();
  }

  Future<String?> _promptGoogleRole() async {
    Set<String> selection = {'parent'};
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Select account type'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'parent', label: Text('Parent')),
                      ButtonSegment(value: 'child', label: Text('Child')),
                    ],
                    selected: selection,
                    onSelectionChanged: (newSelection) => setStateDialog(() => selection = newSelection),
                  )
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(selection.first),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleAuthSuccess(Map<String, dynamic> data, {required String fallbackUsername}) async {
    final token = (data['token'] ?? '').toString();
    final role = (data['role'] ?? '').toString().toLowerCase();
    final username = data['username']?.toString() ?? fallbackUsername;

    if (token.isEmpty) {
      _showSnack('Invalid server response.');
      return;
    }

    AppGlobals.token = token;

    final pref = await PreferencesService.fetchTheme();
    ThemeController.instance.applyPreference(parseThemePreference(pref));

    if (!mounted) return;
    if (role == 'child') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChildHomePage(username: username, token: token),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(username: username, token: token),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username or Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _canSignIn ? () => _signIn() : null,
                      child: const Text('Sign In'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _navigateToCreateAccount(),
                      child: const Text('Create Account'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: (!_googleLoading && GoogleOAuthConfig.isConfigured) ? _signInWithGoogle : null,
                icon: _googleLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              ),
              if (!GoogleOAuthConfig.isConfigured && GoogleOAuthConfig.configurationHint() != null) ...[
                const SizedBox(height: 8),
                Text(
                  GoogleOAuthConfig.configurationHint()!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

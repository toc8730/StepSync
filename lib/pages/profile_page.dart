import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/data/globals.dart';
import 'package:my_app/services/preferences_service.dart';
import 'package:my_app/theme_controller.dart';

import 'create_family_page.dart';
import 'join_family_page.dart';

class ProfilePage extends StatefulWidget {
  final String? initialUsername;
  final String? initialRole; // 'parent' | 'child'

  const ProfilePage({super.key, this.initialUsername, this.initialRole});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = true;
  String? _error;

  String _username = '';
  String _role = ''; // parent | child
  String? _familyName;
  String? _familyIdentifier;
  ThemePreference _themePreference = ThemePreference.system;
  bool _prefsLoading = true;
  String? _prefsError;

  static const _meUrl = 'http://127.0.0.1:5000/me';

  @override
  void initState() {
    super.initState();
    // optimistic defaults from navigation
    _username = widget.initialUsername ?? '';
    _role = (widget.initialRole ?? '').toLowerCase();
    _loading = true;
    _fetchProfile();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _prefsLoading = true;
      _prefsError = null;
    });
    try {
      final theme = await PreferencesService.fetchTheme();
      if (!mounted) return;
      setState(() {
        _themePreference = parseThemePreference(theme);
        _prefsLoading = false;
        _prefsError = null;
      });
      ThemeController.instance.applyPreference(_themePreference);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _prefsLoading = false;
        _prefsError = 'Failed to load preferences: $e';
      });
    }
  }

  Future<void> _updateTheme(ThemePreference pref) async {
    setState(() => _themePreference = pref);
    ThemeController.instance.applyPreference(pref);
    final success = await PreferencesService.updateTheme(themePreferenceToString(pref));
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save theme preference.')),
      );
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final res = await http.get(
        Uri.parse(_meUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AppGlobals.token}',
        },
      );

      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (decoded is Map) {
          _applyMeJson(Map<String, dynamic>.from(decoded));
        } else {
          setState(() {
            _error = 'Unexpected /me payload';
            _loading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Failed to load profile (/me ${res.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error: $e';
        _loading = false;
      });
    }
  }

  void _applyMeJson(Map<String, dynamic> body) {
    final user = (body['user'] is Map)
        ? Map<String, dynamic>.from(body['user'] as Map)
        : const <String, dynamic>{};
    final fams = (body['families'] is List) ? body['families'] as List : const <dynamic>[];

    final username = (user['username'] ?? _username).toString();
    final role = (user['role'] ?? _role).toString().toLowerCase();

    String? famName;
    String? famId;

    if (fams.isNotEmpty && fams.first is Map) {
      final first = Map<String, dynamic>.from(fams.first as Map);
      final fam = (first['family'] is Map)
          ? Map<String, dynamic>.from(first['family'] as Map)
          : const <String, dynamic>{};
      final n = (fam['name'] ?? '').toString();
      final id = (fam['identifier'] ?? '').toString();
      famName = n.isEmpty ? null : n;
      famId = id.isEmpty ? null : id;
    }

    setState(() {
      _username = username;
      _role = role;
      _familyName = famName;
      _familyIdentifier = famId;
      _loading = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isParent = _role == 'parent';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchProfile();
          await _loadPreferences();
        },
        child: ListView(
          children: [
            if (_error != null)
              _errorTile(context, _error!),

            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
              subtitle: Text(_buildProfileSubtitle(isParent)),
              isThreeLine: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.light_mode_outlined),
              title: const Text('Theme'),
              subtitle: Text(_prefsLoading ? 'Loading...' : _themeSubtitle()),
              trailing: DropdownButton<ThemePreference>(
                value: _themePreference,
                onChanged: _prefsLoading ? null : (value) {
                  if (value != null) _updateTheme(value);
                },
                items: ThemePreference.values
                    .map(
                      (pref) => DropdownMenuItem(
                        value: pref,
                        child: Text(_preferenceLabel(pref)),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (_prefsError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  _prefsError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ),
            const Divider(height: 0),

            if (isParent) ...[
              ListTile(
                leading: const Icon(Icons.family_restroom_outlined),
                title: const Text('Create Family'),
                subtitle: const Text('Start a new family group'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateFamilyPage()),
                ),
              ),
              const Divider(height: 0),
            ],
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Join Family'),
              subtitle: const Text('Enter a family identifier to join'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const JoinFamilyPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildProfileSubtitle(bool isParent) {
    final u = _username.isEmpty ? '—' : _username;
    final rolePretty = _role.isEmpty ? '—' : (_role[0].toUpperCase() + _role.substring(1));
    final famName = _familyName ?? 'None';
    final famIdLine = isParent ? '\nFamily Identifier: ${_familyIdentifier ?? 'None'}' : '';
    return 'Username: $u'
           '\nAccount Type: $rolePretty'
           '\nFamily Name: $famName$famIdLine';
  }

  Widget _errorTile(BuildContext context, String msg) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.35),
        border: Border.all(color: Theme.of(context).colorScheme.error.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
          IconButton(
            tooltip: 'Retry',
            onPressed: _fetchProfile,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  String _themeSubtitle() => _preferenceLabel(_themePreference);

  String _preferenceLabel(ThemePreference pref) {
    switch (pref) {
      case ThemePreference.light:
        return 'Light';
      case ThemePreference.dark:
        return 'Dark';
      case ThemePreference.system:
      default:
        return 'System default';
    }
  }
}

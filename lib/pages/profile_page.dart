import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/data/globals.dart';
import 'package:my_app/services/preferences_service.dart';
import 'package:my_app/services/family_service.dart';
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
  bool _membersLoading = false;
  String? _membersError;
  FamilyMembers? _familyMembers;

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
    if (_role == 'parent') {
      _loadFamilyMembers();
    }
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

  Future<void> _loadFamilyMembers() async {
    if (_role != 'parent') return;
    setState(() {
      _membersLoading = true;
      _membersError = null;
    });
    try {
      final members = await FamilyService.fetchMembers();
      if (!mounted) return;
      if (members == null) {
        setState(() {
          _membersLoading = false;
          _familyMembers = null;
          _membersError = 'Unable to load family members.';
        });
      } else {
        setState(() {
          _familyMembers = members;
          _membersLoading = false;
          _membersError = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _membersLoading = false;
        _membersError = 'Failed to load family members: $e';
      });
    }
  }

  Future<void> _removeMember(String username) async {
    final ok = await FamilyService.removeMember(username);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove $username.')),
      );
      return;
    }
    await _loadFamilyMembers();
  }

  Future<void> _transferMaster(String username) async {
    final ok = await FamilyService.transferMaster(username);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to transfer master role.')),
      );
      return;
    }
    await _loadFamilyMembers();
    await _fetchProfile();
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
      if (!(_role == 'parent' && _familyIdentifier != null)) {
        _familyMembers = null;
      }
    });

    if (_role == 'parent' && _familyIdentifier != null) {
      _loadFamilyMembers();
    }
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
          await _loadFamilyMembers();
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
            if (_familyIdentifier != null && _role == 'parent')
              _familyManagementCard(),
            if (_familyIdentifier != null && _role == 'parent')
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
            onPressed: () => _fetchProfile(),
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

  Widget _familyManagementCard() {
    final members = _familyMembers;
    final isMaster = members?.isMaster ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.family_restroom_outlined),
          title: const Text('Family Members'),
          subtitle: Text(_membersLoading
              ? 'Loading members...'
              : members == null
                  ? 'No data available'
                  : '${members.parents.length} parent(s), ${members.children.length} child(ren)'),
          trailing: IconButton(
            tooltip: 'Refresh members',
            onPressed: _membersLoading ? null : () => _loadFamilyMembers(),
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (_membersError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _membersError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
        if (!_membersLoading && members != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Parents', style: TextStyle(fontWeight: FontWeight.w600)),
                ...members.parents.map(
                  (m) => _memberRow(
                    m,
                    canTransfer: isMaster && !m.isMaster,
                    canRemove: isMaster && !m.isMaster,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Children', style: TextStyle(fontWeight: FontWeight.w600)),
                ...members.children.map(
                  (m) => _memberRow(
                    m,
                    canTransfer: false,
                    canRemove: isMaster,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _memberRow(FamilyMember member, {required bool canTransfer, required bool canRemove}) {
    final showTransfer = canTransfer && !member.isMaster;
    final showRemove = canRemove && (!member.isMaster || !canTransfer);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(member.isMaster ? Icons.star : Icons.person_outline),
      title: Text(member.username),
      subtitle: member.isMaster ? const Text('Master parent') : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTransfer)
            IconButton(
              tooltip: 'Make master parent',
              icon: const Icon(Icons.workspace_premium),
              onPressed: () => _transferMaster(member.username),
            ),
          if (showRemove)
            IconButton(
              tooltip: 'Remove from family',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => _removeMember(member.username),
            ),
        ],
      ),
    );
  }
}

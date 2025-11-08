import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:my_app/data/globals.dart';
import 'package:my_app/services/preferences_service.dart';
import 'package:my_app/services/family_service.dart';
import 'package:my_app/services/account_service.dart';
import 'package:my_app/theme_controller.dart';
import 'package:my_app/config/google_oauth_config.dart';

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
  String? _email;
  String _authProvider = 'password';
  String? _familyName;
  String? _familyIdentifier;
  ThemePreference _themePreference = ThemePreference.system;
  bool _prefsLoading = true;
  String? _prefsError;
  bool _membersLoading = false;
  String? _membersError;
  FamilyMembers? _familyMembers;
  final TextEditingController _newUsernameController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _googlePasswordController = TextEditingController();
  bool _showNewPassword = false;
  bool _showCurrentPassword = false;
  bool _showGooglePassword = false;
  bool _updatingCredentials = false;
  bool _switchingGoogle = false;
  String? _accountError;
  String? _accountSuccess;
  String? _googleError;
  String? _googleSuccess;
  bool _leaveLoading = false;
  bool _leaveRequestsLoading = false;
  String? _leaveRequestsError;
  List<LeaveRequestInfo> _leaveRequests = const [];
  late final GoogleSignIn _googleSignIn;

  static const _meUrl = 'http://127.0.0.1:5000/me';

  @override
  void initState() {
    super.initState();
    _googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile', 'openid'],
      clientId: GoogleOAuthConfig.platformClientId,
      serverClientId: GoogleOAuthConfig.serverClientId,
    );
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

  @override
  void dispose() {
    _newUsernameController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _currentPasswordController.dispose();
    _googlePasswordController.dispose();
    super.dispose();
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
    if (_role != 'parent' || _familyIdentifier == null) {
      if (mounted) {
        setState(() {
          _familyMembers = null;
          _leaveRequests = const [];
          _leaveRequestsError = null;
          _leaveRequestsLoading = false;
        });
      }
      return;
    }
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
          _leaveRequests = const [];
          _leaveRequestsError = null;
          _leaveRequestsLoading = false;
        });
      } else {
        setState(() {
          _familyMembers = members;
          _membersLoading = false;
          _membersError = null;
        });
        if (members.isMaster) {
          await _loadLeaveRequests();
        } else {
          if (!mounted) return;
          setState(() {
            _leaveRequests = const [];
            _leaveRequestsError = null;
            _leaveRequestsLoading = false;
          });
        }
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

  Future<void> _handleLeaveRequestAction(String username, bool approve) async {
    try {
      final message = await FamilyService.handleLeaveRequest(username, approve);
      if (!mounted) return;
      _showSnack(message);
      await _loadFamilyMembers();
      await _loadLeaveRequests();
    } catch (e) {
      if (!mounted) return;
      _showSnack(_friendlyError(e));
    }
  }

  Future<void> _confirmLeaveFamily() async {
    if (_familyIdentifier == null || _leaveLoading) return;
    final isParent = _role == 'parent';
    final title = isParent ? 'Leave family' : 'Request to leave family';
    final message = isParent
        ? 'Are you sure you want to leave this family? This cannot be undone.'
        : 'Do you want to request permission from the master parent to leave this family?';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(isParent ? 'Leave' : 'Request')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _leaveLoading = true);
    try {
      final message = await FamilyService.leaveFamily();
      if (!mounted) return;
      _showSnack(message);
      await _fetchProfile();
      await _loadFamilyMembers();
    } catch (e) {
      if (!mounted) return;
      _showSnack(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _leaveLoading = false);
    }
  }

  Future<void> _loadLeaveRequests() async {
    if (!mounted) return;
    if (!(_familyMembers?.isMaster ?? false)) {
      setState(() {
        _leaveRequests = const [];
        _leaveRequestsError = null;
        _leaveRequestsLoading = false;
      });
      return;
    }
    setState(() {
      _leaveRequestsLoading = true;
      _leaveRequestsError = null;
    });
    try {
      final requests = await FamilyService.fetchLeaveRequests();
      if (!mounted) return;
      setState(() {
        _leaveRequests = requests;
        _leaveRequestsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _leaveRequestsError = 'Failed to load leave requests: $e';
        _leaveRequestsLoading = false;
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

  Future<void> _submitCredentialChanges() async {
    final newUsername = _newUsernameController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    final current = _currentPasswordController.text.trim();

    if (newUsername.isEmpty && newPassword.isEmpty) {
      setState(() {
        _accountError = 'Enter a new username and/or password.';
        _accountSuccess = null;
      });
      return;
    }
    if (current.isEmpty) {
      setState(() {
        _accountError = 'Enter your current password to confirm changes.';
        _accountSuccess = null;
      });
      return;
    }
    if (newPassword.isNotEmpty && (newPassword.length < 8 || newPassword.length > 20)) {
      setState(() {
        _accountError = 'New password must be 8–20 characters.';
        _accountSuccess = null;
      });
      return;
    }
    if (newPassword.isNotEmpty && newPassword != confirm) {
      setState(() {
        _accountError = 'New passwords do not match.';
        _accountSuccess = null;
      });
      return;
    }

    setState(() {
      _accountError = null;
      _accountSuccess = null;
      _updatingCredentials = true;
    });

    try {
      final response = await AccountService.updateCredentials(
        currentPassword: current,
        newUsername: newUsername.isEmpty ? null : newUsername,
        newPassword: newPassword.isEmpty ? null : newPassword,
        confirmPassword: newPassword.isEmpty ? null : confirm,
      );
      if (!mounted) return;
      if (response.token != null) {
        AppGlobals.token = response.token!;
      }
      setState(() {
        if (response.username != null) {
          _username = response.username!;
        }
        _accountSuccess = 'Account details updated.';
        _accountError = null;
      });
      _currentPasswordController.clear();
      if (newUsername.isNotEmpty) {
        _newUsernameController.clear();
      }
      if (newPassword.isNotEmpty) {
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      }
      _showSnack('Account updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _accountError = _friendlyError(e);
        _accountSuccess = null;
      });
    } finally {
      if (mounted) {
        setState(() => _updatingCredentials = false);
      }
    }
  }

  Future<void> _switchGoogleAccount() async {
    if (_authProvider != 'google') {
      setState(() {
        _googleError = 'This account is not linked to Google.';
        _googleSuccess = null;
      });
      return;
    }
    final configIssue = GoogleOAuthConfig.configurationHint();
    if (configIssue != null) {
      setState(() {
        _googleError = 'Google sign-in unavailable: $configIssue';
        _googleSuccess = null;
      });
      return;
    }

    final password = _googlePasswordController.text.trim();
    if (password.isEmpty) {
      setState(() {
        _googleError = 'Enter your password to continue.';
        _googleSuccess = null;
      });
      return;
    }

    setState(() {
      _googleError = null;
      _googleSuccess = null;
      _switchingGoogle = true;
    });

    try {
      final account = await _triggerGoogleSelection();
      if (account == null) {
        setState(() => _googleError = 'Google sign-in was cancelled.');
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        setState(() => _googleError = 'Google did not return an ID token.');
        return;
      }

      final response = await AccountService.switchGoogleAccount(
        currentPassword: password,
        idToken: idToken,
      );
      if (!mounted) return;
      if (response.token != null) {
        AppGlobals.token = response.token!;
      }
      setState(() {
        if (response.email != null) {
          _email = response.email;
        }
        _googleSuccess = 'Google account updated.';
        _googleError = null;
      });
      _googlePasswordController.clear();
      _showSnack('Google account updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _googleError = _friendlyError(e);
        _googleSuccess = null;
      });
    } finally {
      if (mounted) {
        setState(() => _switchingGoogle = false);
      }
    }
  }

  Future<GoogleSignInAccount?> _triggerGoogleSelection() async {
    if (!kIsWeb) {
      await _googleSignIn.signOut();
      return _googleSignIn.signIn();
    }
    final silent = await _googleSignIn.signInSilently();
    if (silent != null) return silent;
    final legacy = await _googleSignIn.signIn();
    if (legacy == null) return null;
    return _googleSignIn.signInSilently();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring('Exception: '.length) : text;
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
    final emailRaw = (user['email'] ?? '').toString();
    final providerRaw = (user['auth_provider'] ?? '').toString().toLowerCase();

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
      _email = emailRaw.isEmpty ? null : emailRaw;
      _authProvider = providerRaw.isEmpty ? 'password' : providerRaw;
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
    final inFamily = _familyIdentifier != null;

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
            if (inFamily) _leaveFamilyTile(),
            if (inFamily) const Divider(height: 0),
            _accountSettingsCard(),
            const Divider(height: 0),
            if (_authProvider == 'google') ...[
              _googleAccountCard(),
              const Divider(height: 0),
            ],

            if (isParent) ...[
              ListTile(
                leading: const Icon(Icons.family_restroom_outlined),
                title: const Text('Create Family'),
                subtitle: Text(
                  inFamily
                      ? 'Leave your current family before creating a new one.'
                      : 'Start a new family group',
                ),
                onTap: inFamily
                    ? () => _showSnack('Leave your current family before creating a new one.')
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreateFamilyPage()),
                        ),
              ),
              const Divider(height: 0),
            ],
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Join Family'),
              subtitle: Text(
                inFamily
                    ? 'Leave your current family before joining another.'
                    : 'Enter a family identifier to join',
              ),
              onTap: inFamily
                  ? () => _showSnack('Leave your current family before joining another.')
                  : () => Navigator.of(context).push(
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
    final emailLine = '\nEmail: ${_email ?? '—'}';
    final famIdLine = isParent ? '\nFamily Identifier: ${_familyIdentifier ?? 'None'}' : '';
    return 'Username: $u'
           '$emailLine'
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

  Widget _accountSettingsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Account Settings', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _newUsernameController,
            decoration: const InputDecoration(
              labelText: 'New username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPasswordController,
            obscureText: !_showNewPassword,
            decoration: InputDecoration(
              labelText: 'New password',
              helperText: 'Leave blank to keep your current password.',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showNewPassword = !_showNewPassword),
                icon: Icon(_showNewPassword ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPasswordController,
            obscureText: !_showNewPassword,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currentPasswordController,
            obscureText: !_showCurrentPassword,
            decoration: InputDecoration(
              labelText: 'Current password *',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showCurrentPassword = !_showCurrentPassword),
                icon: Icon(_showCurrentPassword ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Provide your current password to confirm any username or password changes.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _updatingCredentials ? null : _submitCredentialChanges,
            icon: _updatingCredentials
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_updatingCredentials ? 'Saving...' : 'Save changes'),
          ),
          if (_accountError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _accountError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          if (_accountSuccess != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _accountSuccess!,
                style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _leaveFamilyTile() {
    final isParent = _role == 'parent';
    final title = isParent ? 'Leave Family' : 'Request to Leave Family';
    final subtitle = isParent
        ? 'Leave immediately and transfer responsibilities automatically.'
        : 'Send a request to the master parent to leave.';
    return ListTile(
      leading: Icon(isParent ? Icons.logout : Icons.outbox),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: _leaveLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _leaveLoading ? null : _confirmLeaveFamily,
    );
  }

  Widget _googleAccountCard() {
    final configIssue = GoogleOAuthConfig.configurationHint();
    final disabled = configIssue != null || _switchingGoogle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Google Account', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Currently linked: ${_email ?? 'Unknown'}'),
          const SizedBox(height: 12),
          TextField(
            controller: _googlePasswordController,
            obscureText: !_showGooglePassword,
            decoration: InputDecoration(
              labelText: 'Password *',
              helperText: 'Confirm with your password before switching Google accounts.',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showGooglePassword = !_showGooglePassword),
                icon: Icon(_showGooglePassword ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: disabled ? null : _switchGoogleAccount,
            icon: _switchingGoogle
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz),
            label: Text(_switchingGoogle ? 'Switching...' : 'Switch Google account'),
          ),
          if (configIssue != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Google sign-in unavailable: $configIssue',
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          if (_googleError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _googleError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          if (_googleSuccess != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _googleSuccess!,
                style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
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
                  : _familyMembersSubtitle(members)),
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
        if ((_familyMembers?.isMaster ?? false)) _leaveRequestsPanel(),
      ],
    );
  }

  String _familyMembersSubtitle(FamilyMembers members) {
    final base = '${members.parents.length} parent(s), ${members.children.length} child(ren)';
    if (members.isMaster && members.pendingRequests > 0) {
      return '$base\nPending leave requests: ${members.pendingRequests}';
    }
    return base;
  }

  Widget _leaveRequestsPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Leave Requests', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_leaveRequestsLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),
          if (_leaveRequestsError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _leaveRequestsError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          if (!_leaveRequestsLoading && _leaveRequestsError == null && _leaveRequests.isEmpty)
            const Text('No pending requests.'),
          ..._leaveRequests.map(
            (req) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.child_care_outlined),
              title: Text(req.childUsername),
              subtitle: Text(_formatRequestTime(req.requestedAt)),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: _leaveRequestsLoading ? null : () => _handleLeaveRequestAction(req.childUsername, true),
                  ),
                  IconButton(
                    tooltip: 'Reject',
                    icon: const Icon(Icons.cancel, color: Colors.redAccent),
                    onPressed: _leaveRequestsLoading ? null : () => _handleLeaveRequestAction(req.childUsername, false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRequestTime(DateTime? timestamp) {
    if (timestamp == null) return 'Requested just now';
    final local = timestamp.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final year = local.year;
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return 'Requested $month/$day/$year at $hour12:$minute $period';
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

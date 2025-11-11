import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:my_app/config/backend_config.dart';
import 'package:my_app/data/globals.dart';
import 'package:my_app/services/preferences_service.dart';
import 'package:my_app/services/family_service.dart';
import 'package:my_app/services/account_service.dart';
import 'package:my_app/theme_controller.dart';
import 'package:my_app/config/google_oauth_config.dart';

import 'create_family_page.dart';
import 'join_family_page.dart';

String _friendlyErrorMessage(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring('Exception: '.length) : text;
}

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
  String _displayName = '';
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
  final TextEditingController _inviteChildController = TextEditingController();
  bool _updatingCredentials = false;
  bool _switchingGoogle = false;
  bool _unlinkingGoogle = false;
  bool _sendingInvite = false;
  String? _googleError;
  String? _googleSuccess;
  String? _inviteError;
  String? _inviteSuccess;
  bool _leaveLoading = false;
  bool _leaveRequestsLoading = false;
  String? _leaveRequestsError;
  List<LeaveRequestInfo> _leaveRequests = const [];
  bool _respondingInvite = false;
  bool _childInvitesLoading = false;
  String? _childInvitesError;
  List<FamilyInviteInfo> _childInvites = const [];
  late final GoogleSignIn _googleSignIn;

  static const _meUrl = '${BackendConfig.baseUrl}/me';

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
    _inviteChildController.dispose();
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
      _showSnack(_friendlyErrorMessage(e));
    }
  }

  Future<void> _respondToInvite(FamilyInviteInfo invite, bool accept) async {
    setState(() => _respondingInvite = true);
    try {
      await FamilyService.respondToInvite(familyId: invite.familyId, accept: accept);
      await _loadChildInvites();
      if (accept) {
        await _fetchProfile();
        await _loadFamilyMembers();
        _showSnack('Joined ${invite.familyName}.');
      } else {
        _showSnack('Invite declined.');
      }
    } catch (e) {
      _showSnack(_friendlyErrorMessage(e));
      await _loadChildInvites();
    } finally {
      if (mounted) setState(() => _respondingInvite = false);
    }
  }

  Future<void> _sendChildInvite() async {
    final username = _inviteChildController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _inviteError = 'Enter a child username to invite.';
        _inviteSuccess = null;
      });
      return;
    }
    setState(() {
      _sendingInvite = true;
      _inviteError = null;
      _inviteSuccess = null;
    });
    try {
      await FamilyService.sendInvite(username);
      if (!mounted) return;
      setState(() {
        _inviteSuccess = 'Invitation sent to $username.';
        _inviteError = null;
      });
      _inviteChildController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inviteError = _friendlyErrorMessage(e);
        _inviteSuccess = null;
      });
    } finally {
      if (mounted) setState(() => _sendingInvite = false);
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
      final localLabel = (_role == 'child') ? _currentLocalRequestLabel() : null;
      final message = await FamilyService.leaveFamily(requestedLocalLabel: localLabel);
      if (!mounted) return;
      _showSnack(message);
      await _fetchProfile();
      await _loadFamilyMembers();
    } catch (e) {
      if (!mounted) return;
      _showSnack(_friendlyErrorMessage(e));
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

  Future<void> _loadChildInvites() async {
    if (_role != 'child') {
      if (mounted) {
        setState(() {
          _childInvites = const [];
          _childInvitesError = null;
          _childInvitesLoading = false;
        });
      }
      return;
    }
    setState(() {
      _childInvitesLoading = true;
      _childInvitesError = null;
    });
    try {
      final invites = await FamilyService.fetchChildInvites();
      if (!mounted) return;
      setState(() {
        _childInvites = invites;
        _childInvitesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _childInvitesError = 'Failed to load invites: $e';
        _childInvitesLoading = false;
      });
    }
  }

  Future<void> _showUsernameDialog() async {
    final controller = TextEditingController();
    final password = TextEditingController();
    String? error;
    bool busy = false;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Change username'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'New username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Usernames must be 1–100 characters.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final newName = controller.text.trim();
                        final current = password.text.trim();
                        if (newName.isEmpty) {
                          setStateDialog(() => error = 'Enter a new username.');
                          return;
                        }
                        if (newName.length > 100) {
                          setStateDialog(() => error = 'Username must be at most 100 characters.');
                          return;
                        }
                        if (current.isEmpty) {
                          setStateDialog(() => error = 'Enter your current password.');
                          return;
                        }
                        setStateDialog(() {
                          busy = true;
                          error = null;
                        });
                        final result = await _performCredentialUpdate(
                          newUsername: newName,
                          currentPassword: current,
                        );
                        if (result == null) {
                          if (mounted) _showSnack('Username updated.');
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          setStateDialog(() {
                            busy = false;
                            error = result;
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDisplayNameDialog() async {
    final controller = TextEditingController(text: _displayName);
    final password = TextEditingController();
    String? error;
    bool busy = false;
    final needsCurrent = (_authProvider != 'google');
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Change display name'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'New display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (needsCurrent)
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                      border: OutlineInputBorder(),
                    ),
                  )
                else
                  Text(
                    'Google-linked account: no current password needed.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                Text(
                  'Display names must be 1–100 characters.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final newName = controller.text.trim();
                        final current = password.text.trim();
                        if (newName.isEmpty) {
                          setStateDialog(() => error = 'Enter a display name.');
                          return;
                        }
                        if (newName.length > 100) {
                          setStateDialog(() => error = 'Display name must be at most 100 characters.');
                          return;
                        }
                        if (needsCurrent && current.isEmpty) {
                          setStateDialog(() => error = 'Enter your current password.');
                          return;
                        }
                        setStateDialog(() {
                          busy = true;
                          error = null;
                        });
                        final result = await _performCredentialUpdate(
                          newDisplayName: newName,
                          currentPassword: needsCurrent ? current : '',
                        );
                        if (result == null) {
                          if (mounted) _showSnack('Display name updated.');
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          setStateDialog(() {
                            busy = false;
                            error = result;
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showPasswordDialog() async {
    final newPass = TextEditingController();
    final confirm = TextEditingController();
    final current = TextEditingController();
    final needsCurrent = (_authProvider != 'google');
    String? error;
    bool busy = false;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Change password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newPass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (needsCurrent)
                  Column(
                    children: [
                      TextField(
                        controller: current,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Current password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Google-linked account: no current password needed. You can still use Google sign-in afterward.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Text(
                  'Passwords must be 8–20 characters.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final newPassword = newPass.text;
                        final confirmPassword = confirm.text;
                        final currentPassword = current.text.trim();
                        if (newPassword.length < 8 || newPassword.length > 20) {
                          setStateDialog(() => error = 'Password must be 8–20 characters.');
                          return;
                        }
                        if (newPassword != confirmPassword) {
                          setStateDialog(() => error = 'Passwords do not match.');
                          return;
                        }
                        if (needsCurrent && currentPassword.isEmpty) {
                          setStateDialog(() => error = 'Enter your current password.');
                          return;
                        }
                        setStateDialog(() {
                          busy = true;
                          error = null;
                        });
                        final result = await _performCredentialUpdate(
                          newPassword: newPassword,
                          confirmPassword: confirmPassword,
                          currentPassword: needsCurrent ? currentPassword : '',
                        );
                        if (result == null) {
                          if (mounted) _showSnack('Password updated.');
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          setStateDialog(() {
                            busy = false;
                            error = result;
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showUnlinkGoogleDialog() async {
    final displayCtrl = TextEditingController(text: _displayName);
    final usernameCtrl = TextEditingController(text: _username);
    final passwordCtrl = TextEditingController();
    String? error;
    bool busy = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Remove Google sign-in'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: displayCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Choose a password',
                    helperText: '8–20 characters',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final display = displayCtrl.text.trim();
                        final username = usernameCtrl.text.trim();
                        final password = passwordCtrl.text;
                        if (display.isEmpty) {
                          setStateDialog(() => error = 'Enter a display name.');
                          return;
                        }
                        if (username.isEmpty) {
                          setStateDialog(() => error = 'Enter a username.');
                          return;
                        }
                        if (password.length < 8 || password.length > 20) {
                          setStateDialog(() => error = 'Password must be 8–20 characters.');
                          return;
                        }
                        setStateDialog(() {
                          busy = true;
                          error = null;
                        });
                        final result = await _performUnlinkGoogle(
                          displayName: display,
                          username: username,
                          password: password,
                        );
                        if (result == null && context.mounted) {
                          Navigator.of(context).pop();
                        } else {
                          setStateDialog(() {
                            busy = false;
                            error = result;
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Remove link'),
              ),
            ],
          );
        },
      ),
    );

    displayCtrl.dispose();
    usernameCtrl.dispose();
    passwordCtrl.dispose();
  }

  Future<void> _showFamilyNameDialog() async {
    if (!(_familyMembers?.isMaster ?? false)) return;
    final controller = TextEditingController(text: _familyName ?? '');
    final password = TextEditingController();
    String? error;
    bool busy = false;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Rename family'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'New family name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current family password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Family names can be up to 16 characters.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final newName = controller.text.trim();
                        final currentPassword = password.text.trim();
                        if (newName.isEmpty) {
                          setStateDialog(() => error = 'Enter a family name.');
                          return;
                        }
                        if (newName.length > 16) {
                          setStateDialog(() => error = 'Family name must be 16 characters or fewer.');
                          return;
                        }
                        if (currentPassword.isEmpty) {
                          setStateDialog(() => error = 'Enter the current family password.');
                          return;
                        }
                        setStateDialog(() {
                          busy = true;
                          error = null;
                        });
                        final result = await _performFamilyUpdate(
                          newName: newName,
                          currentPassword: currentPassword,
                        );
                        if (result == null) {
                          await _fetchProfile();
                          if (mounted) _showSnack('Family name updated.');
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          setStateDialog(() {
                            busy = false;
                            error = result;
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showFamilyPasswordDialog() async {
    if (!(_familyMembers?.isMaster ?? false)) return;
    final newPass = TextEditingController();
    final confirm = TextEditingController();
    final current = TextEditingController();
    String? error;
    bool busy = false;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Change family password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newPass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New family password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new family password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: current,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current family password',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final newPassword = newPass.text;
                        final confirmPassword = confirm.text;
                        final currentPassword = current.text.trim();
                        if (newPassword.length < 8 || newPassword.length > 20) {
                          setStateDialog(() => error = 'Password must be 8–20 characters.');
                          return;
                        }
                        if (newPassword != confirmPassword) {
                          setStateDialog(() => error = 'Passwords do not match.');
                          return;
                        }
                        if (currentPassword.isEmpty) {
                          setStateDialog(() => error = 'Enter the current family password.');
                          return;
                        }
                        setStateDialog(() {
                          busy = true;
                          error = null;
                        });
                        final result = await _performFamilyUpdate(
                          newPassword: newPassword,
                          confirmPassword: confirmPassword,
                          currentPassword: currentPassword,
                        );
                        if (result == null) {
                          await _fetchProfile();
                          if (mounted) _showSnack('Family password updated.');
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          setStateDialog(() {
                            busy = false;
                            error = result;
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _performCredentialUpdate({
    String? newUsername,
    String? newPassword,
    String? confirmPassword,
    String? newDisplayName,
    required String currentPassword,
  }) async {
    setState(() => _updatingCredentials = true);
    try {
      final response = await AccountService.updateCredentials(
        currentPassword: currentPassword,
        newUsername: (newUsername?.trim().isEmpty ?? true) ? null : newUsername!.trim(),
        newPassword: (newPassword?.isEmpty ?? true) ? null : newPassword,
        confirmPassword: (confirmPassword?.isEmpty ?? true) ? null : confirmPassword,
        newDisplayName: (newDisplayName?.trim().isEmpty ?? true) ? null : newDisplayName!.trim(),
      );
      if (!mounted) return 'Operation cancelled.';
      if (response.token != null) {
        AppGlobals.token = response.token!;
      }
      if (response.username != null) {
        setState(() => _username = response.username!);
      }
      if (response.displayName != null) {
        setState(() => _displayName = response.displayName!);
      }
      return null;
    } catch (e) {
      return _friendlyErrorMessage(e);
    } finally {
      if (mounted) setState(() => _updatingCredentials = false);
    }
  }

  Future<String?> _performFamilyUpdate({
    String? newName,
    String? newPassword,
    String? confirmPassword,
    required String currentPassword,
  }) async {
    try {
      final message = await FamilyService.updateFamily(
        newName: (newName?.trim().isEmpty ?? true) ? null : newName!.trim(),
        newPassword: (newPassword?.isEmpty ?? true) ? null : newPassword,
        currentPassword: currentPassword,
      );
      if (!mounted) return 'Operation cancelled.';
      if (message.isNotEmpty) {
        await _fetchProfile();
        await _loadFamilyMembers();
      }
      return null;
    } catch (e) {
      return _friendlyErrorMessage(e);
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

  Future<void> _linkGoogleAccount() async => _connectGoogleAccount(linking: true);

  Future<void> _switchGoogleAccount() async => _connectGoogleAccount(linking: false);

  Future<void> _connectGoogleAccount({required bool linking}) async {
    if (!linking && _authProvider != 'google') {
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

    setState(() {
      _googleError = null;
      _googleSuccess = null;
      _switchingGoogle = true;
    });

    try {
      final account = await _triggerGoogleSelection(forcePrompt: true);
      if (account == null) {
        setState(() => _googleError = 'Google sign-in was cancelled.');
        return;
      }
      final tokens = await _obtainGoogleTokens(account);
      if (!tokens.hasCredential) {
        setState(() => _googleError = 'Google did not return a usable credential.');
        return;
      }
      if (!linking) {
        final normalizedCurrent = (_email ?? '').toLowerCase();
        if (normalizedCurrent.isNotEmpty && account.email.toLowerCase() == normalizedCurrent) {
          setState(() => _googleError = 'That Google account is already linked.');
          return;
        }
      }

      final response = await AccountService.switchGoogleAccount(
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
      if (!mounted) return;
      if (response.token != null) {
        AppGlobals.token = response.token!;
      }
      await _fetchProfile();
      setState(() {
        if (response.email != null) {
          _email = response.email;
        }
        if (linking) {
          _authProvider = 'google';
        }
        _googleSuccess = linking ? 'Google account linked.' : 'Google account updated.';
        _googleError = null;
      });
      _showSnack(_googleSuccess ?? 'Google account updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _googleError = _friendlyErrorMessage(e);
        _googleSuccess = null;
      });
    } finally {
      if (mounted) {
        setState(() => _switchingGoogle = false);
      }
    }
  }

  Future<String?> _performUnlinkGoogle({
    required String displayName,
    required String username,
    required String password,
  }) async {
    setState(() => _unlinkingGoogle = true);
    try {
      final response = await AccountService.unlinkGoogleAccount(
        displayName: displayName,
        username: username,
        password: password,
      );
      if (!mounted) return 'Operation cancelled.';
      if (response.token != null) {
        AppGlobals.token = response.token!;
      }
      setState(() {
        _authProvider = 'password';
        _username = response.username ?? username;
        _displayName = response.displayName ?? displayName;
        _googleSuccess = 'Google account removed. Use your username & password next time.';
        _googleError = null;
      });
      await _fetchProfile();
      return null;
    } catch (e) {
      return _friendlyErrorMessage(e);
    } finally {
      if (mounted) setState(() => _unlinkingGoogle = false);
    }
  }

  Future<_GoogleAuthTokens> _obtainGoogleTokens(GoogleSignInAccount account) async {
    Future<_GoogleAuthTokens> tokensFor(GoogleSignInAccount acc) async {
      final auth = await acc.authentication;
      final id = (auth.idToken?.isNotEmpty ?? false) ? auth.idToken : null;
      final access = (auth.accessToken?.isNotEmpty ?? false) ? auth.accessToken : null;
      return _GoogleAuthTokens(idToken: id, accessToken: access);
    }

    final direct = await tokensFor(account);
    if (direct.hasCredential) return direct;

    final refreshed = await _googleSignIn.signInSilently();
    if (refreshed != null) {
      final retry = await tokensFor(refreshed);
      if (retry.hasCredential) return retry;
    }

    await _googleSignIn.signOut();
    final reauth = await _googleSignIn.signInSilently();
    if (reauth != null) {
      final fallback = await tokensFor(reauth);
      if (fallback.hasCredential) return fallback;
    }
    return const _GoogleAuthTokens();
  }

  Future<GoogleSignInAccount?> _triggerGoogleSelection({bool forcePrompt = false}) async {
    if (kIsWeb) {
      if (!forcePrompt) {
        final silent = await _googleSignIn.signInSilently();
        if (silent != null) return silent;
      } else {
        await _googleSignIn.signOut();
      }
      final legacy = await _googleSignIn.signIn();
      if (legacy == null) return null;
      final refreshed = await _googleSignIn.signInSilently();
      return refreshed ?? legacy;
    }

    if (forcePrompt) {
      await _googleSignIn.signOut();
    }
    return _googleSignIn.signIn();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    final rawDisplay = (user['display_name'] ?? _displayName).toString();
    final displayName = rawDisplay.trim().isEmpty ? username : rawDisplay;
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
      _displayName = displayName;
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
    if (_role == 'child') {
      _loadChildInvites();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isParent = _role == 'parent';
    final inFamily = _familyIdentifier != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = _horizontalPadding(constraints.maxWidth);
          return RefreshIndicator(
            onRefresh: () async {
              await _fetchProfile();
              await _loadPreferences();
              await _loadFamilyMembers();
              await _loadChildInvites();
            },
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
              children: [
                if (_error != null)
                  _errorTile(context, _error!),
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Profile'),
                    subtitle: _buildProfileSubtitle(isParent),
                    isThreeLine: true,
                  ),
                ),
                if (isParent)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: ListTile(
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
                              ).then((value) {
                                _fetchProfile();
                                _loadPreferences();
                                if (_role == 'parent') {
                                  _loadFamilyMembers();
                                }
                              }),
                    ),
                  ),
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  child: ListTile(
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
                            ).then((value) {
                              _fetchProfile();
                              _loadPreferences();
                              if (_role == 'parent') {
                                _loadFamilyMembers();
                              }
                            }),
                  ),
                ),
                if (inFamily) _leaveFamilyTile(),
                if (_familyIdentifier != null && _role == 'parent') ...[
                  _familyManagementCard(),
                  if (_familyMembers?.isMaster ?? false) _familySettingsCard(),
                ],
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  child: ListTile(
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
                ),
                if (_prefsError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _prefsError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                    ),
                ),
                if (_role == 'child') _childInvitesCard(),
                _accountSettingsCard(),
                if (_authProvider == 'google')
                  _googleAccountCard()
                else
                  _googleLinkCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileSubtitle(bool isParent) {
    final lines = <String>[
      'Username: ${_username.isEmpty ? '—' : _username}',
      'Display Name: ${_displayName.isEmpty ? '—' : _displayName}',
      'Email: ${_email ?? '—'}',
      'Account Type: ${_role.isEmpty ? '—' : (_role[0].toUpperCase() + _role.substring(1))}',
      'Family Name: ${_familyName ?? 'None'}',
    ];
    if (!isParent) {
      return Text(lines.join('\n'));
    }
    final id = _familyIdentifier;
    final hasId = id != null && id.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) Text(line),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text('Family Identifier: ${hasId ? id : 'None'}'),
            ),
            if (hasId)
              IconButton(
                tooltip: 'Copy family identifier',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                iconSize: 16,
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: id!));
                  _showSnack('Family identifier copied.');
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _errorTile(BuildContext context, String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
    final isGoogle = (_authProvider == 'google');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.contact_page_outlined),
            title: const Text('Change username'),
            subtitle: Text('Current: $_username'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showUsernameDialog,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Change display name'),
            subtitle: Text('Current: $_displayName'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showDisplayNameDialog,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Change password'),
            subtitle: Text(isGoogle
                ? 'Set a fallback password in addition to Google sign-in.'
                : 'Update your account password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showPasswordDialog,
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListTile(
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
      ),
    );
  }

  Widget _googleAccountCard() {
    final configIssue = GoogleOAuthConfig.configurationHint();
    final disabled = configIssue != null || _switchingGoogle;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Google Account', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Currently linked: ${_email ?? 'Unknown'}'),
            const SizedBox(height: 12),
            Text(
              'Pick a different Google account to relink this profile.',
              style: Theme.of(context).textTheme.bodySmall,
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
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (configIssue != null || _unlinkingGoogle) ? null : _showUnlinkGoogleDialog,
              icon: _unlinkingGoogle
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link_off),
              label: Text(_unlinkingGoogle ? 'Removing...' : 'Remove Google link'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _googleLinkCard() {
    final configIssue = GoogleOAuthConfig.configurationHint();
    final disabled = configIssue != null || _switchingGoogle;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Link Google for quick sign-in', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Connect a Google account so you can sign in with one tap and share secure tokens across devices.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: disabled ? null : _linkGoogleAccount,
              icon: _switchingGoogle
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link),
              label: Text(_switchingGoogle ? 'Linking...' : 'Link Google account'),
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
      ),
    );
  }

  Widget _familyManagementCard() {
    final members = _familyMembers;
    final isMaster = members?.isMaster ?? false;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
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
                      (m) => _buildMemberRow(
                        m,
                        canTransfer: isMaster && !m.isMaster,
                        canRemove: isMaster && !m.isMaster,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Children', style: TextStyle(fontWeight: FontWeight.w600)),
                    ...members.children.map(
                      (m) => _buildMemberRow(
                        m,
                        canTransfer: false,
                        canRemove: isMaster,
                      ),
                    ),
                  ],
                ),
              ),
            if ((_familyMembers?.isMaster ?? false)) _buildLeaveRequestsPanel(),
            if (_role == 'parent') _buildFamilyInviteCard(),
          ],
        ),
      ),
    );
  }

  Widget _familySettingsCard() {
    final isMaster = _familyMembers?.isMaster ?? false;
    final currentName = _familyName ?? 'Not set';
    final familyId = _familyIdentifier ?? 'Unknown';
    if (!isMaster) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 12),
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Family settings'),
          subtitle: Text('Only the master parent can update this family.\nID: $familyId'),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.family_restroom_outlined),
            title: const Text('Family name'),
            subtitle: Text('Current: $currentName\nID: $familyId'),
            trailing: FilledButton.icon(
              onPressed: _showFamilyNameDialog,
              icon: const Icon(Icons.edit),
              label: const Text('Rename'),
            ),
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Family password'),
            subtitle: const Text('Protects who can join this family'),
            trailing: FilledButton.icon(
              onPressed: _showFamilyPasswordDialog,
              icon: const Icon(Icons.lock_reset),
              label: const Text('Change'),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildFamilyInviteCard() {
    if (_role != 'parent' || _familyIdentifier == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invite a Child', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _inviteChildController,
              decoration: const InputDecoration(
                labelText: 'Child username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sendingInvite ? null : _sendChildInvite,
              icon: _sendingInvite
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_sendingInvite ? 'Sending...' : 'Send invite'),
            ),
            if (_inviteError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _inviteError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ),
            if (_inviteSuccess != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _inviteSuccess!,
                  style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _childInvitesCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Family Invitations', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_childInvitesLoading)
              const LinearProgressIndicator()
            else if (_childInvitesError != null)
              Text(
                _childInvitesError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              )
            else if (_childInvites.isEmpty)
              const Text('No invitations right now.'),
            if (!_childInvitesLoading && _childInvites.isNotEmpty)
              ..._childInvites.map(
                (invite) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "You're invited to join the \"${invite.familyName}\" family",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('Family ID: ${invite.familyId}'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Accept invite',
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: _respondingInvite ? null : () => _respondToInvite(invite, true),
                      ),
                      IconButton(
                        tooltip: 'Decline invite',
                        icon: const Icon(Icons.cancel, color: Colors.redAccent),
                        onPressed: _respondingInvite ? null : () => _respondToInvite(invite, false),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _familyMembersSubtitle(FamilyMembers members) {
    final base = '${members.parents.length} parent(s), ${members.children.length} child(ren)';
    if (members.isMaster && members.pendingRequests > 0) {
      return '$base\nPending leave requests: ${members.pendingRequests}';
    }
    return base;
  }

  Widget _buildLeaveRequestsPanel() {
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
              title: Text(req.displayName),
              subtitle: Text('${_formatLeaveRequestTime(req)}\n@${req.childUsername}'),
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

  String _formatLeaveRequestTime(LeaveRequestInfo req) {
    final label = req.childLocalTime?.trim();
    if (label != null && label.isNotEmpty) {
      return 'Requested $label';
    }
    final timestamp = req.requestedAt;
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

  String _currentLocalRequestLabel() {
    final now = DateTime.now();
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthName = monthNames[now.month - 1];
    final day = now.day;
    final year = now.year;
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
    final offsetMinutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$monthName $day, $year $hour12:$minute $period (UTC$sign$offsetHours:$offsetMinutes)';
  }

  Widget _buildMemberRow(FamilyMember member, {required bool canTransfer, required bool canRemove}) {
    final showTransfer = canTransfer && !member.isMaster;
    final showRemove = canRemove && (!member.isMaster || !canTransfer);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(member.isMaster ? Icons.star : Icons.person_outline),
      title: Text(member.displayName),
      subtitle: Text(
        member.isMaster ? 'Master parent (@${member.username})' : '@${member.username}',
      ),
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

  double _horizontalPadding(double maxWidth) {
    const maxContentWidth = 640.0;
    if (!maxWidth.isFinite) return 16;
    final side = (maxWidth - maxContentWidth) / 2;
    return math.max(16, side);
  }
}

class _GoogleAuthTokens {
  const _GoogleAuthTokens({this.idToken, this.accessToken});

  final String? idToken;
  final String? accessToken;

  bool get hasCredential => (idToken?.isNotEmpty ?? false) || (accessToken?.isNotEmpty ?? false);
}

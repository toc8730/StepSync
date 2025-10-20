// lib/pages/notifications.dart
import 'package:flutter/material.dart';
import '../services/push_notifications.dart';
import 'package:flutter/services.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String? _token;
  bool _loadingToken = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final t = await PushNotifications.getToken();
    setState(() {
      _token = t;
      _loadingToken = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('FCM Device Token', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _loadingToken
                  ? const Text('Loading...')
                  : SelectableText(_token ?? 'No token'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _token == null
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: _token!));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Token copied to clipboard')),
                            );
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy token'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // re-fetch token (useful after reinstall/permission change)
                      setState(() => _loadingToken = true);
                      await _loadToken();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh token'),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text('Topics (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await PushNotifications.subscribe('announcements');
                      if (!mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Subscribed to "announcements"')));
                    },
                    child: const Text('Subscribe to "announcements"'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await PushNotifications.unsubscribe('announcements');
                      if (!mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Unsubscribed from "announcements"')));
                    },
                    child: const Text('Unsubscribe'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Send yourself a test from Firebase Console → Cloud Messaging using this token or the "announcements" topic.',
            ),
          ],
        ),
      ),
    );
  }
}
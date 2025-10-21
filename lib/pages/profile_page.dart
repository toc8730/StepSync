import 'package:flutter/material.dart';
import 'create_family_page.dart';
import 'join_family_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final buttonStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Replace with real user info later
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: const Text('Your Profile'),
                subtitle: const Text('User details coming soon'),
              ),
            ),
            const SizedBox(height: 16),

            Text('Family', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: buttonStyle,
                    icon: const Icon(Icons.group_add),
                    label: const Text('Create Family'),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CreateFamilyPage()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: buttonStyle,
                    icon: const Icon(Icons.group),
                    label: const Text('Join Family'),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JoinFamilyPage()),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Text(
              'Create a new family by choosing a name (1–16 chars) and setting a password. '
              'Or join an existing family using its Family ID and password.',
            ),
          ],
        ),
      ),
    );
  }
}
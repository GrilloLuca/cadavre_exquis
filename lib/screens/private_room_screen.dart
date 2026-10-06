import 'package:cadavre_exquisite/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/button.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/private_room.dart';
import 'package:cadavre_exquisite/screens/create_private_room_screen.dart';
import 'package:cadavre_exquisite/screens/join_private_room_screen.dart';

/// Entry point for private rooms: lets the user create a new room or join
/// an existing one. Pops with the resulting [PrivateRoom] so the caller
/// (the home screen) can switch into it, or with null if the user backs out
/// without creating or joining a room.
class PrivateRoomScreen extends StatelessWidget {
  const PrivateRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.privateRoomTitle),
        backgroundColor: AppColors.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Icon(
              Icons.lock_outline,
              size: 64.0,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16.0),
            Text(
              l10n.privateRoomDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 32.0),
            ChatButton(
              text: l10n.createRoomButton,
              color: AppColors.primary,
              onPressed: () async {
                final room = await Navigator.push<PrivateRoom>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreatePrivateRoomScreen(),
                  ),
                );
                if (room != null && context.mounted) {
                  Navigator.pop(context, room);
                }
              },
            ),
            ChatButton(
              text: l10n.joinRoomButton,
              color: AppColors.primaryDark,
              onPressed: () async {
                final room = await Navigator.push<PrivateRoom>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const JoinPrivateRoomScreen(),
                  ),
                );
                if (room != null && context.mounted) {
                  Navigator.pop(context, room);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

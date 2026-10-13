import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/auth_error.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/account/view_models/account_view_model.dart';
import 'package:cadavre_exquisite/ui/account/widgets/delete_account_dialog.dart';
import 'package:cadavre_exquisite/ui/account/widgets/nickname_card.dart';
import 'package:cadavre_exquisite/ui/account/widgets/notifications_card.dart';
import 'package:cadavre_exquisite/ui/account/widgets/room_card.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/welcome_screen.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/private_room/widgets/private_room_screen.dart';

/// The profile tab: nickname, room, notifications, sign-out and account
/// deletion. Creates
/// its [AccountViewModel] once, in `initState` (see `ChatScreen`).
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final AccountViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = AccountViewModel(
      profileRepository: context.read<UserProfileRepository>(),
      authRepository: context.read<AuthRepository>(),
      roomRepository: context.read<RoomRepository>(),
      notificationRepository: context.read<NotificationRepository>(),
    );
    _viewModel.deleteAccount.addListener(_onDeleteChanged);
    _viewModel.signOut.addListener(_onSignOutChanged);
  }

  @override
  void dispose() {
    _viewModel.deleteAccount.removeListener(_onDeleteChanged);
    _viewModel.signOut.removeListener(_onSignOutChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _goToWelcome() {
    Navigator.pushNamedAndRemoveUntil(
      context,
      WelcomeScreen.id,
      (route) => false,
    );
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.red),
    );
  }

  void _onSignOutChanged() {
    final signOut = _viewModel.signOut;
    if (signOut.running) return;
    if (signOut.error != null) {
      signOut.clearResult();
      _showError(AppLocalizations.of(context)!.genericError);
      return;
    }
    if (signOut.completed) _goToWelcome();
  }

  /// Asks for confirmation (and the password, for email/password users),
  /// then deletes the account.
  Future<void> _deleteAccount() async {
    final confirmation = await showDialog<DeleteConfirmation>(
      context: context,
      builder: (_) =>
          DeleteAccountDialog(usesPassword: _viewModel.usesPassword),
    );
    if (confirmation == null || !mounted) return;
    _viewModel.deleteAccount.execute(confirmation.password);
  }

  void _onDeleteChanged() {
    final delete = _viewModel.deleteAccount;
    if (delete.running) return;
    final l10n = AppLocalizations.of(context)!;
    final error = delete.error;
    if (error != null) {
      delete.clearResult();
      _showError(error is AuthException &&
              error.code == AuthErrorCode.invalidCredentials
          ? l10n.loginInvalidCredentials
          : l10n.genericError);
      return;
    }
    // False: the user dismissed the Google account picker.
    if (delete.completed && delete.value == true) {
      // Shown by the app's messenger, so it outlives this screen.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
      _goToWelcome();
    }
  }

  Future<void> _openPrivateRoomPicker() async {
    final l10n = AppLocalizations.of(context)!;
    final room = await Navigator.push<PrivateRoom>(
      context,
      MaterialPageRoute(builder: (_) => const PrivateRoomScreen()),
    );
    if (room == null || !mounted) return;
    _viewModel.enterPrivateRoom(room);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.privateRoomJoinedSnackbar(room.name))),
      );
  }

  static bool _showsNotifications(NotificationPermission? permission) =>
      permission != null && permission != NotificationPermission.unsupported;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _viewModel,
        _viewModel.loadNickname,
        _viewModel.saveNickname,
        _viewModel.deleteAccount,
        _viewModel.signOut,
        _viewModel.enableNotifications,
      ]),
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final email = _viewModel.email;
    final isDeleting = _viewModel.deleteAccount.running;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              // Keep the content vertically centred when it fits, and let it
              // scroll when it doesn't (e.g. with the keyboard open).
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48.0).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Center(
                        child: CircleAvatar(
                          radius: 40.0,
                          backgroundColor: AppColors.primary,
                          child: Icon(
                            Icons.person,
                            size: 40.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      Text(
                        email ?? '',
                        style: const TextStyle(
                          fontSize: 18.0,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (email != null) ...[
                        const SizedBox(height: 24.0),
                        NicknameCard(viewModel: _viewModel),
                      ],
                      const SizedBox(height: 24.0),
                      RoomCard(
                        viewModel: _viewModel,
                        onOpenPrivateRooms: _openPrivateRoomPicker,
                      ),
                      if (email != null &&
                          _showsNotifications(
                              _viewModel.notificationPermission)) ...[
                        const SizedBox(height: 24.0),
                        NotificationsCard(viewModel: _viewModel),
                      ],
                      const SizedBox(height: 32.0),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _viewModel.signOut.running
                              ? null
                              : _viewModel.signOut.execute,
                          icon: const Icon(Icons.logout),
                          label: Text(l10n.logoutButton),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      if (email != null) ...[
                        const SizedBox(height: 16.0),
                        Center(
                          child: TextButton(
                            onPressed: isDeleting ? null : _deleteAccount,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: isDeleting
                                ? const SizedBox(
                                    width: 18.0,
                                    height: 18.0,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                    ),
                                  )
                                : Text(l10n.deleteAccountButton),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

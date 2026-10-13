import 'package:flutter/material.dart';

import 'package:cadavre_exquisite/domain/models/story_language.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/account/view_models/account_view_model.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';

/// The room section of the profile: the language rooms, the private room
/// the user is in (with a way to leave it) and the entry to join or create
/// one. Rebuilt by its parent when [viewModel] changes.
class RoomCard extends StatelessWidget {
  const RoomCard({
    super.key,
    required this.viewModel,
    required this.onOpenPrivateRooms,
  });

  final AccountViewModel viewModel;

  /// Opens the private room screen (create or join).
  final VoidCallback onOpenPrivateRooms;

  Widget _buildLanguageRow(StoryLanguage language) {
    final isSelected = language.code == viewModel.languageCode;
    final inPrivateRoom = viewModel.privateRoom != null;
    // In a private room the selected row only marks the room the user goes
    // back to, so it drops the fill that means "you are here".
    final isFilled = isSelected && !inPrivateRoom;
    final ink =
        inPrivateRoom ? AppColors.ink.withValues(alpha: 0.75) : AppColors.ink;

    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: isSelected,
        button: true,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isFilled ? 8.0 : 0.0),
          child: ListTile(
            minTileHeight: 48.0,
            contentPadding:
                EdgeInsets.symmetric(horizontal: isFilled ? 8.0 : 16.0),
            tileColor: isFilled ? AppColors.sage : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
            leading: ExcludeSemantics(
              child: Text(
                language.flag,
                style: const TextStyle(fontSize: 24.0),
              ),
            ),
            title: Text(
              language.nativeName,
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: ink,
              ),
            ),
            trailing: isSelected
                ? Icon(
                    inPrivateRoom ? Icons.check : Icons.check_circle,
                    size: 24.0,
                    color: AppColors.primaryDark,
                  )
                : null,
            onTap: () => viewModel.selectLanguage(language.code),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final privateRoom = viewModel.privateRoom;
    final secondaryStyle = TextStyle(
      fontSize: 14.0,
      color: AppColors.ink.withValues(alpha: 0.75),
    );
    final caption = switch (viewModel.languageSource) {
      RoomLanguageSource.explicit => null,
      RoomLanguageSource.detected => l10n.languageRoomAutoDetected,
      RoomLanguageSource.fallback => l10n.languageRoomAutoFallback,
    };
    const chevron = Icon(Icons.chevron_right);

    return CreamCard(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    l10n.roomSectionTitle,
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(l10n.roomSectionDescription, style: secondaryStyle),
              ],
            ),
          ),
          const SizedBox(height: 12.0),
          if (privateRoom != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: AppColors.sage,
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Row(
                children: <Widget>[
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.lock,
                      size: 20.0,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      l10n.privateRoomActiveNotice(privateRoom.name),
                      style: const TextStyle(
                        fontSize: 14.0,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12.0),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Semantics(
              header: true,
              child: Text(
                l10n.languageRoomHeading,
                style: const TextStyle(
                  fontSize: 14.0,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4.0),
          for (final language in kStoryLanguages) _buildLanguageRow(language),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 0.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.smartphone,
                      size: 16.0,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Expanded(
                    child: Text(
                      caption,
                      style: secondaryStyle.copyWith(fontSize: 13.0),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 24.0, indent: 16.0, endIndent: 16.0),
          ListTileTheme.merge(
            iconColor: AppColors.ink.withValues(alpha: 0.6),
            child: privateRoom == null
                ? ListTile(
                    minTileHeight: 56.0,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16.0),
                    leading: const Icon(
                      Icons.lock_outline,
                      size: 24.0,
                      color: AppColors.primary,
                    ),
                    title: Text(
                      l10n.privateRoomMenuItem,
                      style: const TextStyle(
                        fontSize: 16.0,
                        color: AppColors.ink,
                      ),
                    ),
                    subtitle: Text(
                      l10n.privateRoomRowSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: secondaryStyle,
                    ),
                    trailing: chevron,
                    onTap: onOpenPrivateRooms,
                  )
                : ListTile(
                    minTileHeight: 56.0,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16.0),
                    leading: const Icon(
                      Icons.lock,
                      size: 24.0,
                      color: AppColors.primaryDark,
                    ),
                    title: Text(
                      privateRoom.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    subtitle:
                        Text(l10n.privateRoomMenuItem, style: secondaryStyle),
                    trailing: chevron,
                    onTap: onOpenPrivateRooms,
                  ),
          ),
          if (privateRoom != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0.0, 8.0, 0.0),
                child: TextButton.icon(
                  onPressed: viewModel.leavePrivateRoom,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                  ),
                  icon: const Icon(Icons.logout),
                  label: Text(l10n.leavePrivateRoomMenuItem),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

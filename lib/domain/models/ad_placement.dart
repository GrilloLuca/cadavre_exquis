/// Where a banner ad is shown in the app. Each placement has its own ad unit
/// so they can be tracked separately in the AdMob console.
///
/// Ads only appear on read-only screens: never while writing, nor on the
/// login, account or room screens.
enum AdPlacement {
  /// Above the navigation bar, on the completed-stories tab.
  completeStoriesBanner,

  /// At the bottom of the story reader.
  storyReadBanner,
}

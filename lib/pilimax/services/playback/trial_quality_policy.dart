abstract final class TrialQualityPolicy {
  static bool shouldRequestWebTryLook({
    required bool isLoggedIn,
    required bool allowAnonymous1080,
  }) => !isLoggedIn && allowAnonymous1080;

  static bool canRequestOfficialPreview({
    required bool hasPreview,
    required bool unlimitedTrialEnabled,
    bool? canWatch,
    int? times,
  }) =>
      hasPreview &&
      canWatch != false &&
      (unlimitedTrialEnabled || times == null || times > 0);

  static bool canUseOfficialPreview({
    required bool hasPreview,
    required bool hasPlayableStream,
    required bool hasPlaybackError,
    required bool isDrm,
    required bool unlimitedTrialEnabled,
    bool? canWatch,
    int? times,
  }) =>
      hasPlayableStream &&
      !hasPlaybackError &&
      !isDrm &&
      canRequestOfficialPreview(
        hasPreview: hasPreview,
        unlimitedTrialEnabled: unlimitedTrialEnabled,
        canWatch: canWatch,
        times: times,
      );
}

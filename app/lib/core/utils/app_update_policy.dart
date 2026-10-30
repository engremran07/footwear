class AppUpdateDecision {
  const AppUpdateDecision({
    required this.isRequired,
    required this.hasOptionalUpdate,
    required this.canStartImmediateUpdate,
    required this.canStartFlexibleUpdate,
  });

  final bool isRequired;
  final bool hasOptionalUpdate;
  final bool canStartImmediateUpdate;
  final bool canStartFlexibleUpdate;
}

class AppUpdatePolicy {
  AppUpdatePolicy._();

  static const int requiredUpdatePriority = 4;

  static AppUpdateDecision evaluate({
    required int currentVersionCode,
    required int minimumSupportedVersionCode,
    required bool updateAvailable,
    required int? availableVersionCode,
    required int updatePriority,
    required bool flexibleUpdateAllowed,
    required bool immediateUpdateAllowed,
    bool immediateUpdateInProgress = false,
  }) {
    final hasNewerUpdate =
        updateAvailable &&
        availableVersionCode != null &&
        availableVersionCode > currentVersionCode;
    final isRequired =
        (minimumSupportedVersionCode > 0 &&
            currentVersionCode < minimumSupportedVersionCode) ||
        immediateUpdateInProgress ||
        (hasNewerUpdate && updatePriority >= requiredUpdatePriority);

    return AppUpdateDecision(
      isRequired: isRequired,
      hasOptionalUpdate: hasNewerUpdate && !isRequired,
      canStartImmediateUpdate:
          isRequired &&
          (hasNewerUpdate || immediateUpdateInProgress) &&
          immediateUpdateAllowed,
      canStartFlexibleUpdate:
          hasNewerUpdate && !isRequired && flexibleUpdateAllowed,
    );
  }
}

class WorkspaceAdminAccessPolicy {
  static const String documentId = 'platform_access_policy';
  static const int defaultMaxDevicesAllowed = 3;
  static const int defaultMaxActiveSessionsAllowed = 2;
  static const int maximumSlotsPerUser = 10;

  final int maxDevicesAllowed;
  final int maxActiveSessionsAllowed;

  const WorkspaceAdminAccessPolicy({
    this.maxDevicesAllowed = defaultMaxDevicesAllowed,
    this.maxActiveSessionsAllowed = defaultMaxActiveSessionsAllowed,
  }) : assert(
         maxDevicesAllowed >= 1 && maxDevicesAllowed <= maximumSlotsPerUser,
       ),
       assert(
         maxActiveSessionsAllowed >= 1 &&
             maxActiveSessionsAllowed <= maximumSlotsPerUser,
       );

  factory WorkspaceAdminAccessPolicy.fromJson(Map<String, dynamic>? json) {
    return WorkspaceAdminAccessPolicy(
      maxDevicesAllowed: _readLimit(
        json,
        'workspace_admin_max_devices_allowed',
        defaultMaxDevicesAllowed,
      ),
      maxActiveSessionsAllowed: _readLimit(
        json,
        'workspace_admin_max_active_sessions_allowed',
        defaultMaxActiveSessionsAllowed,
      ),
    );
  }

  static int _readLimit(
    Map<String, dynamic>? json,
    String field,
    int defaultValue,
  ) {
    final rawValue = json?[field];
    if (rawValue == null) return defaultValue;
    if (rawValue is! num ||
        rawValue.toDouble() != rawValue.toInt().toDouble() ||
        rawValue < 1 ||
        rawValue > maximumSlotsPerUser) {
      throw FormatException('Invalid workspace-admin access limit: $field');
    }
    return rawValue.toInt();
  }

  Map<String, dynamic> toJson() => {
    'workspace_admin_max_devices_allowed': maxDevicesAllowed,
    'workspace_admin_max_active_sessions_allowed': maxActiveSessionsAllowed,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceAdminAccessPolicy &&
          other.maxDevicesAllowed == maxDevicesAllowed &&
          other.maxActiveSessionsAllowed == maxActiveSessionsAllowed);

  @override
  int get hashCode => Object.hash(maxDevicesAllowed, maxActiveSessionsAllowed);
}

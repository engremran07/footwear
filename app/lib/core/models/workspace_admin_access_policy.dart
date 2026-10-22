class WorkspaceAdminAccessPolicy {
  static const String documentId = 'platform_access_policy';
  static const int defaultMaxActiveSessionsAllowed = 2;
  static const int maximumActiveSessionsAllowed = 10;

  final int maxActiveSessionsAllowed;

  const WorkspaceAdminAccessPolicy({
    this.maxActiveSessionsAllowed = defaultMaxActiveSessionsAllowed,
  }) : assert(
         maxActiveSessionsAllowed >= 1 &&
             maxActiveSessionsAllowed <= maximumActiveSessionsAllowed,
       );

  factory WorkspaceAdminAccessPolicy.fromJson(Map<String, dynamic>? json) {
    return WorkspaceAdminAccessPolicy(
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
        rawValue > maximumActiveSessionsAllowed) {
      throw FormatException('Invalid workspace-admin access limit: $field');
    }
    return rawValue.toInt();
  }

  Map<String, dynamic> toJson() => {
    'workspace_admin_max_active_sessions_allowed': maxActiveSessionsAllowed,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceAdminAccessPolicy &&
          other.maxActiveSessionsAllowed == maxActiveSessionsAllowed);

  @override
  int get hashCode => maxActiveSessionsAllowed.hashCode;
}

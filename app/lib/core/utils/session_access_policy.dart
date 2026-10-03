import '../../models/session_model.dart';

class SessionAccessPolicy {
  const SessionAccessPolicy._();

  static SessionModel? currentForDevice(
    Iterable<SessionModel> sessions, {
    required String deviceId,
    required DateTime now,
    String? userId,
  }) {
    final activeSessions =
        sessions.where((session) {
            if (session.deviceId != deviceId) return false;
            if (session.status != 'active') return false;
            if (userId != null && session.userId != userId) return false;
            return session.expiresAt?.toDate().isAfter(now) ?? false;
          }).toList()
          ..sort((left, right) => right.lastSeenAt.compareTo(left.lastSeenAt));
    return activeSessions.isEmpty ? null : activeSessions.first;
  }
}

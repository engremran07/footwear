import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/collections.dart';

Future<void> writeRateLimitedNotification({
  required FirebaseFirestore db,
  required String actorUid,
  required Map<String, dynamic> data,
}) async {
  final normalizedActorUid = actorUid.trim();
  if (normalizedActorUid.isEmpty) {
    throw ArgumentError('actorUid must not be empty');
  }

  final batch = db.batch();
  batch.set(db.collection(Collections.notifications).doc(), {
    ...data,
    'created_by': normalizedActorUid,
    'created_at': FieldValue.serverTimestamp(),
  });
  batch.update(db.collection(Collections.users).doc(normalizedActorUid), {
    'last_notification_at': FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

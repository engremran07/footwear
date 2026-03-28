const functions = require('firebase-functions');
const admin = require('firebase-admin');

exports.manageUserAuth = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign-in required.');
  }

  const callerUid = context.auth.uid;
  const db = admin.firestore();
  const callerDoc = await db.collection('users').doc(callerUid).get();
  if (!callerDoc.exists) {
    throw new functions.https.HttpsError('permission-denied', 'Caller profile not found.');
  }

  const callerRole = String(callerDoc.data().role || '').trim().toLowerCase();
  if (callerRole !== 'admin' && callerRole !== 'manager') {
    throw new functions.https.HttpsError('permission-denied', 'Admin access required.');
  }

  const targetUid = String(data.targetUid || '').trim();
  const newEmail = typeof data.newEmail === 'string' ? data.newEmail.trim().toLowerCase() : '';
  const newPassword = typeof data.newPassword === 'string' ? data.newPassword.trim() : '';

  if (!targetUid) {
    throw new functions.https.HttpsError('invalid-argument', 'targetUid is required.');
  }
  if (!newEmail && !newPassword) {
    throw new functions.https.HttpsError('invalid-argument', 'Provide newEmail and/or newPassword.');
  }
  if (newPassword && newPassword.length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
  }

  const targetDoc = await db.collection('users').doc(targetUid).get();
  if (!targetDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Target user not found.');
  }

  const targetRole = String(targetDoc.data().role || '').trim().toLowerCase();
  if (targetRole !== 'seller') {
    throw new functions.https.HttpsError('permission-denied', 'Only seller accounts can be updated.');
  }

  const updatePayload = {};
  if (newEmail) updatePayload.email = newEmail;
  if (newPassword) updatePayload.password = newPassword;

  try {
    await admin.auth().updateUser(targetUid, updatePayload);

    if (newEmail) {
      await db.collection('users').doc(targetUid).update({
        email: newEmail,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return {
      success: true,
      emailUpdated: !!newEmail,
      passwordUpdated: !!newPassword,
    };
  } catch (error) {
    functions.logger.error('manageUserAuth failed', { callerUid, targetUid, error });
    const code = error.code || 'internal';
    throw new functions.https.HttpsError(code, error.message || 'Failed to update auth user.');
  }
});

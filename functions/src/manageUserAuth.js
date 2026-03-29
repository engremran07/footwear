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

  const action = String(data.action || 'updateUser').trim();
  const targetUid = String(data.targetUid || '').trim();
  const newEmail = typeof data.newEmail === 'string' ? data.newEmail.trim().toLowerCase() : '';
  const newPassword = typeof data.newPassword === 'string' ? data.newPassword.trim() : '';

  if (action === 'createUser') {
    const email = typeof data.email === 'string' ? data.email.trim().toLowerCase() : '';
    const password = typeof data.password === 'string' ? data.password.trim() : '';
    const displayName = typeof data.displayName === 'string' ? data.displayName.trim() : '';
    const roleRaw = typeof data.role === 'string' ? data.role.trim().toLowerCase() : 'seller';
    const role = roleRaw === 'manager' ? 'admin' : (roleRaw === 'admin' ? 'admin' : 'seller');
    const assignedRouteId = typeof data.assignedRouteId === 'string' ? data.assignedRouteId.trim() : '';
    const assignedRouteName = typeof data.assignedRouteName === 'string' ? data.assignedRouteName.trim() : '';

    if (!email || !password || !displayName) {
      throw new functions.https.HttpsError('invalid-argument', 'email, password, and displayName are required.');
    }
    if (password.length < 6) {
      throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
    }
    if (role === 'seller' && !assignedRouteId) {
      throw new functions.https.HttpsError('invalid-argument', 'Seller accounts require assignedRouteId.');
    }

    const routeName = assignedRouteName || null;

    try {
      const created = await admin.auth().createUser({
        email,
        password,
        displayName,
      });

      const now = admin.firestore.FieldValue.serverTimestamp();
      await db.collection('users').doc(created.uid).set({
        email,
        display_name: displayName,
        role,
        assigned_route_id: role === 'seller' ? assignedRouteId : null,
        assigned_route_name: role === 'seller' ? routeName : null,
        active: true,
        created_at: now,
        updated_at: now,
      });

      if (role === 'seller') {
        await db.collection('routes').doc(assignedRouteId).update({
          assigned_seller_id: created.uid,
          assigned_seller_name: displayName,
          updated_at: now,
        });
      }

      return {
        success: true,
        action,
        uid: created.uid,
      };
    } catch (error) {
      functions.logger.error('manageUserAuth createUser failed', { callerUid, error });
      const code = error.code || 'internal';
      throw new functions.https.HttpsError(code, error.message || 'Failed to create user.');
    }
  }

  if (action === 'deleteUser') {
    if (!targetUid) {
      throw new functions.https.HttpsError('invalid-argument', 'targetUid is required.');
    }

    const targetDoc = await db.collection('users').doc(targetUid).get();
    if (!targetDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Target user not found.');
    }

    const targetRole = String(targetDoc.data().role || '').trim().toLowerCase();
    if (targetRole === 'admin' || targetRole === 'manager') {
      throw new functions.https.HttpsError('permission-denied', 'Admin users cannot be deleted.');
    }

    try {
      const now = admin.firestore.FieldValue.serverTimestamp();
      const routeSnap = await db.collection('routes')
        .where('assigned_seller_id', '==', targetUid)
        .limit(20)
        .get();

      const batch = db.batch();
      for (const routeDoc of routeSnap.docs) {
        batch.update(routeDoc.ref, {
          assigned_seller_id: null,
          assigned_seller_name: null,
          updated_at: now,
        });
      }
      batch.delete(db.collection('users').doc(targetUid));
      await batch.commit();

      try {
        await admin.auth().deleteUser(targetUid);
      } catch (authErr) {
        // If auth record is already gone, Firestore cleanup still stands.
        if (String(authErr.code || '') !== 'auth/user-not-found') {
          throw authErr;
        }
      }

      return {
        success: true,
        action,
        uid: targetUid,
      };
    } catch (error) {
      functions.logger.error('manageUserAuth deleteUser failed', { callerUid, targetUid, error });
      const code = error.code || 'internal';
      throw new functions.https.HttpsError(code, error.message || 'Failed to delete user.');
    }
  }

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

const admin = require('firebase-admin');
const functions = require('firebase-functions');

/**
 * Send a push notification to a specific user by their Firestore UID.
 * Reads the fcm_token from the users collection.
 *
 * @param {string} userId - Firestore user ID
 * @param {string} title - Notification title
 * @param {string} body - Notification body text
 * @param {Object} [data] - Optional data payload for the notification
 */
async function sendToUser(userId, title, body, data = {}) {
  try {
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) {
      functions.logger.warn(`sendToUser: user ${userId} not found`);
      return;
    }
    const token = userDoc.data().fcm_token;
    if (!token) {
      functions.logger.info(`sendToUser: no FCM token for user ${userId}`);
      return;
    }
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: { ...data, click_action: 'FLUTTER_NOTIFICATION_CLICK' },
      android: {
        notification: {
          channelId: 'high_importance_channel',
          priority: 'high',
          sound: 'default',
        },
      },
    });
    functions.logger.info(`sendToUser: sent to ${userId} — "${title}"`);
  } catch (err) {
    // Token may be stale; log but don't crash
    if (err.code === 'messaging/registration-token-not-registered' ||
        err.code === 'messaging/invalid-registration-token') {
      functions.logger.warn(`sendToUser: stale token for ${userId}, clearing`);
      await admin.firestore().collection('users').doc(userId).update({
        fcm_token: admin.firestore.FieldValue.delete(),
      });
    } else {
      functions.logger.error(`sendToUser: failed for ${userId}`, err);
    }
  }
}

/**
 * Send a push notification to an FCM topic.
 *
 * @param {string} topic - Topic name (e.g., 'admins', 'managers', 'all_users')
 * @param {string} title - Notification title
 * @param {string} body - Notification body text
 * @param {Object} [data] - Optional data payload
 */
async function sendToTopic(topic, title, body, data = {}) {
  try {
    await admin.messaging().send({
      topic,
      notification: { title, body },
      data: { ...data, click_action: 'FLUTTER_NOTIFICATION_CLICK' },
      android: {
        notification: {
          channelId: 'high_importance_channel',
          priority: 'high',
          sound: 'default',
        },
      },
    });
    functions.logger.info(`sendToTopic: sent to topic "${topic}" — "${title}"`);
  } catch (err) {
    functions.logger.error(`sendToTopic: failed for topic "${topic}"`, err);
  }
}

/**
 * Send a push notification to all users with a specific role.
 *
 * @param {string} role - User role (admin, manager, viewer, etc.)
 * @param {string} title - Notification title
 * @param {string} body - Notification body text
 * @param {Object} [data] - Optional data payload
 */
async function sendToRole(role, title, body, data = {}) {
  return sendToTopic(role, title, body, data);
}

module.exports = { sendToUser, sendToTopic, sendToRole };

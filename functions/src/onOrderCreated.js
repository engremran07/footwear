const functions = require('firebase-functions');
const admin = require('firebase-admin');

/**
 * onOrderCreated
 *
 * Trigger: orders/{orderId} — onCreate
 *
 * When a new order is created:
 * 1. Set order status to 'processing' (if it was created as 'pending')
 * 2. No inventory reservation happens here — that happens per order_item
 *    via onOrderItemAdded.
 */
exports.onOrderCreated = functions.firestore
  .document('orders/{orderId}')
  .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const { orderId } = context.params;
    const order = snap.data();

    try {
      // Guard: only process orders in 'pending' state
      if (order.status !== 'pending') {
        functions.logger.info(`onOrderCreated: order ${orderId} skipped (status=${order.status})`);
        return null;
      }

      await db.collection('orders').doc(orderId).update({
        status: 'processing',
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      functions.logger.info(`onOrderCreated: order ${orderId} moved to processing`);
      return null;
    } catch (err) {
      functions.logger.error(`onOrderCreated: failed for order ${orderId}`, err);
      throw err;
    }
  });

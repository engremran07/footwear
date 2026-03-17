const functions = require('firebase-functions');
const admin = require('firebase-admin');

/**
 * onOrderItemAdded
 *
 * Trigger: order_items/{itemId} — onCreate
 *
 * When an order item is added:
 * 1. Find available inventory_items matching product_id + size
 * 2. Reserve the required qty (status → 'reserved')
 * 3. Decrement product stock_count
 * 4. Write back inventory_batch_id to the order_item for cost tracking
 *
 * Uses a transaction to avoid race conditions on stock.
 */
exports.onOrderItemAdded = functions.firestore
  .document('order_items/{itemId}')
  .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const { itemId } = context.params;
    const item = snap.data();

    const { order_id, product_id, size, qty } = item;

    if (!product_id || !size || !qty) {
      functions.logger.warn(`onOrderItemAdded: missing fields on item ${itemId}`);
      return null;
    }

    try {
      await db.runTransaction(async (t) => {
        // Find available inventory items for this product + size
        const candidatesSnap = await db
          .collection('inventory_items')
          .where('product_id', '==', product_id)
          .where('size', '==', size)
          .where('status', '==', 'available')
          .limit(qty)
          .get();

        if (candidatesSnap.size < qty) {
          functions.logger.warn(
            `onOrderItemAdded: insufficient stock for product ${product_id} size ${size}. ` +
            `needed=${qty} available=${candidatesSnap.size}`
          );
          // Mark order item as stock_issue so UI can show the problem
          t.update(snap.ref, {
            status: 'stock_issue',
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          return;
        }

        let inventory_batch_id = null;

        // Reserve the items
        candidatesSnap.docs.forEach((docSnap) => {
          t.update(docSnap.ref, {
            status: 'reserved',
            order_id,
            order_item_id: itemId,
            reserved_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          // Track batch from first item (all from same batch ideally)
          if (!inventory_batch_id) {
            inventory_batch_id = docSnap.data().inventory_batch_id;
          }
        });

        // Write batch reference back to order_item
        t.update(snap.ref, {
          inventory_batch_id,
          status: 'reserved',
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Decrement product stock_count
        const productRef = db.collection('products').doc(product_id);
        t.update(productRef, {
          stock_count: admin.firestore.FieldValue.increment(-qty),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      functions.logger.info(`onOrderItemAdded: reserved ${qty} pairs for item ${itemId}`);
      return null;
    } catch (err) {
      functions.logger.error(`onOrderItemAdded: failed for item ${itemId}`, err);
      throw err;
    }
  });

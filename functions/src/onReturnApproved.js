const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { sendToTopic } = require('./notificationHelper');

/**
 * onReturnApproved
 *
 * Trigger: order_returns/{returnId} — onUpdate where status changes to 'approved'
 *
 * Logic per returned item:
 *   condition === 'good'    → inventory_item.status = 'available'
 *                              products.stock_count += qty_returned
 *   condition === 'damaged' → create waste_records doc(s)
 *                              inventory_item.status = 'disposed'
 *
 * Also marks fully-returned order_items as status = 'returned'.
 *
 * IMPORTANT: This function does NOT write to pnl_snapshots or cash_transactions.
 * Cash refund is logged manually by manager via the /cash screen.
 */
exports.onReturnApproved = functions.firestore
  .document('order_returns/{returnId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Only run when status transitions to 'approved'
    if (before.status === after.status || after.status !== 'approved') {
      return null;
    }

    const db = admin.firestore();
    const { returnId } = context.params;
    const items = Array.isArray(after.items) ? after.items : [];

    functions.logger.info(`onReturnApproved: processing return ${returnId} with ${items.length} item lines`);

    try {
      await db.runTransaction(async (t) => {
        // Read all affected inventory_items inside the transaction for consistency
        const itemReads = [];
        for (const ri of items) {
          const invQuery = db
            .collection('inventory_items')
            .where('order_item_id', '==', ri.order_item_id)
            .where('status', '==', 'sold')
            .limit(ri.qty_returned);
          const invSnap = await t.get(invQuery);
          itemReads.push({ ri, invDocs: invSnap.docs });
        }

        for (const { ri, invDocs } of itemReads) {
          const { qty_returned, condition, reason, product_id, size, order_item_id } = ri;

          if (condition === 'good') {
            // Restock inventory items
            for (const invDoc of invDocs) {
              t.update(invDoc.ref, {
                status: 'available',
                order_id: admin.firestore.FieldValue.delete(),
                order_item_id: admin.firestore.FieldValue.delete(),
                reserved_at: admin.firestore.FieldValue.delete(),
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
            // Increment stock_count on product
            if (product_id && qty_returned > 0) {
              const productRef = db.collection('products').doc(product_id);
              t.update(productRef, {
                stock_count: admin.firestore.FieldValue.increment(qty_returned),
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          } else if (condition === 'damaged') {
            // Mark inventory items as disposed + create waste records
            for (const invDoc of invDocs) {
              t.update(invDoc.ref, {
                status: 'disposed',
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
              });

              const wasteRef = db.collection('waste_records').doc();
              t.set(wasteRef, {
                qc_record_id: null,
                batch_id: invDoc.data().inventory_batch_id || null,
                product_id: product_id || null,
                size: size || null,
                inventory_item_id: invDoc.id,
                worker_id: null,
                reason: reason || 'customer_return_damaged',
                disposed: false,
                disposed_at: null,
                created_at: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          }

          // Mark the order_item as returned
          if (order_item_id) {
            const orderItemRef = db.collection('order_items').doc(order_item_id);
            t.update(orderItemRef, {
              status: 'returned',
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        }

        // Update return doc to reflect processing complete
        t.update(change.after.ref, {
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      functions.logger.info(`onReturnApproved: completed successfully for ${returnId}`);

      // Push notification: return approved
      const customerName = after.customer_name || 'Unknown';
      const totalQty = after.total_qty_returned || 0;
      await sendToTopic(
        'managers',
        'Return Approved',
        `${customerName} \u2014 ${totalQty} pairs returned`,
        { route: `/returns/${returnId}`, type: 'return_approved' }
      );

      return null;
    } catch (err) {
      functions.logger.error(`onReturnApproved: error for ${returnId}`, err);
      throw err;
    }
  });

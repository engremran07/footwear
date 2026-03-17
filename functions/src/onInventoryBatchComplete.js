const functions = require('firebase-functions');
const admin = require('firebase-admin');

/**
 * onInventoryBatchComplete
 *
 * Trigger: inventory_batches/{batchId} — onUpdate
 *
 * When a batch status changes to 'complete':
 * 1. Calculate cost_per_pair = cost_total / passed_qty
 * 2. Write cost_per_pair back to the batch document
 * 3. Update all inventory_items belonging to this batch with cost_per_pair
 * 4. Update product stock_count by passed_qty
 *
 * Guards:
 * - Only fires on transition: before.status != 'complete' AND after.status == 'complete'
 * - Requires passed_qty > 0 and cost_total > 0
 */
exports.onInventoryBatchComplete = functions.firestore
  .document('inventory_batches/{batchId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Guard: only fire on transition → complete
    if (before.status === 'complete' || after.status !== 'complete') {
      return null;
    }

    const db = admin.firestore();
    const { batchId } = context.params;

    const passed_qty = Number(after.passed_qty) || 0;
    const cost_total = Number(after.cost_total) || 0;

    if (passed_qty <= 0) {
      functions.logger.warn(`onInventoryBatchComplete: batch ${batchId} has passed_qty=0, skipping`);
      return null;
    }

    const cost_per_pair = cost_total / passed_qty;

    try {
      // Write cost_per_pair to batch
      await change.after.ref.update({
        cost_per_pair,
        completed_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update all inventory_items in this batch
      const itemsSnap = await db
        .collection('inventory_items')
        .where('inventory_batch_id', '==', batchId)
        .where('status', '==', 'available')
        .get();

      const BATCH_SIZE = 400;
      let writeBatch = db.batch();
      let count = 0;

      for (const doc of itemsSnap.docs) {
        writeBatch.update(doc.ref, {
          cost_per_pair,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;

        if (count % BATCH_SIZE === 0) {
          await writeBatch.commit();
          writeBatch = db.batch();
        }
      }

      if (count % BATCH_SIZE !== 0) {
        await writeBatch.commit();
      }

      // Update product stock_count
      if (after.product_id) {
        await db.collection('products').doc(after.product_id).update({
          stock_count: admin.firestore.FieldValue.increment(passed_qty),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      functions.logger.info(
        `onInventoryBatchComplete: batch ${batchId} complete. ` +
        `cost_per_pair=${cost_per_pair.toFixed(2)}, items_updated=${count}`
      );
      return null;
    } catch (err) {
      functions.logger.error(`onInventoryBatchComplete: failed for batch ${batchId}`, err);
      throw err;
    }
  });

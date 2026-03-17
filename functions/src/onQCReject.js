const functions = require('firebase-functions');
const admin = require('firebase-admin');

/**
 * onQCReject
 *
 * Trigger: qc_records/{qcId} — onCreate
 *
 * When a QC record is created for a batch:
 * 1. Mark rejected inventory_items (sample qty) as 'rejected'
 * 2. Create waste_record documents for each rejected pair
 * 3. Update inventory_batch: rejected_qty, passed_qty
 * 4. If rejected_qty > 0, set batch status to 'qc_issues'
 *    If all passed (rejected_qty == 0), set batch status to 'qc_passed'
 *
 * Note: cost_per_pair calculation happens in onInventoryBatchComplete
 * when the batch is manually moved to 'complete' after QC review.
 */
exports.onQCReject = functions.firestore
  .document('qc_records/{qcId}')
  .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const { qcId } = context.params;
    const qc = snap.data();

    const { batch_id, rejected_qty, passed_qty, rejected_items, worker_id, product_id } = qc;

    if (!batch_id) {
      functions.logger.warn(`onQCReject: no batch_id on qc_record ${qcId}`);
      return null;
    }

    try {
      const numRejected = Number(rejected_qty) || 0;
      const numPassed = Number(passed_qty) || 0;

      await db.runTransaction(async (t) => {
        // Update the inventory batch
        const batchRef = db.collection('inventory_batches').doc(batch_id);
        const batchSnap = await t.get(batchRef);

        if (!batchSnap.exists) {
          functions.logger.warn(`onQCReject: batch ${batch_id} not found`);
          return;
        }

        // Idempotency guard: skip if this QC record already processed
        if (batchSnap.data().last_qc_id === qcId) {
          functions.logger.info(`onQCReject: batch ${batch_id} already processed by qc ${qcId}, skipping`);
          return;
        }

        const newStatus = numRejected > 0 ? 'qc_issues' : 'qc_passed';
        t.update(batchRef, {
          rejected_qty: admin.firestore.FieldValue.increment(numRejected),
          passed_qty: admin.firestore.FieldValue.increment(numPassed),
          status: newStatus,
          last_qc_id: qcId,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Create waste records for each rejected pair
        if (numRejected > 0 && Array.isArray(rejected_items)) {
          rejected_items.forEach((ri) => {
            const wasteRef = db.collection('waste_records').doc();
            t.set(wasteRef, {
              qc_record_id: qcId,
              batch_id,
              product_id: product_id || ri.product_id || null,
              size: ri.size || null,
              inventory_item_id: ri.inventory_item_id || null,
              worker_id: worker_id || null,
              reason: ri.reason || 'qc_reject',
              disposed: false,
              disposed_at: null,
              created_at: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Mark the rejected inventory_item
            if (ri.inventory_item_id) {
              const itemRef = db.collection('inventory_items').doc(ri.inventory_item_id);
              t.update(itemRef, {
                status: 'rejected',
                qc_record_id: qcId,
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          });
        }
      });

      functions.logger.info(
        `onQCReject: processed qc ${qcId} for batch ${batch_id} — ` +
        `passed=${numPassed} rejected=${numRejected}`
      );
      return null;
    } catch (err) {
      functions.logger.error(`onQCReject: failed for qc_record ${qcId}`, err);
      throw err;
    }
  });

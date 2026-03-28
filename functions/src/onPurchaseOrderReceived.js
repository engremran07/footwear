const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { sendToTopic } = require('./notificationHelper');

/**
 * onPurchaseOrderReceived
 *
 * Trigger: purchase_orders/{poId} — onUpdate
 *
 * When a PO status changes to 'received':
 * 1. For each line item in the PO, create inventory_items
 * 2. Create an inventory_batch record (or update existing draft batch)
 * 3. Update supplier.total_purchased
 *
 * PO items format:
 * items: [{ product_id, size, qty, unit_cost, product_name }]
 */
exports.onPurchaseOrderReceived = functions.firestore
  .document('purchase_orders/{poId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Guard: only fire on transition → received
    if (before.status === 'received' || after.status !== 'received') {
      return null;
    }

    const db = admin.firestore();
    const { poId } = context.params;
    const { supplier_id, items, total } = after;

    if (!items || !Array.isArray(items) || items.length === 0) {
      functions.logger.warn(`onPurchaseOrderReceived: no items on PO ${poId}`);
      return null;
    }

    try {
      // Create an inventory batch for this PO
      const batchRef = db.collection('inventory_batches').doc();
      const batchId = batchRef.id;
      const qty_total = items.reduce((sum, i) => sum + (Number(i.qty) || 0), 0);

      // Build all inventory_item docs to create
      const itemDocs = [];
      for (const lineItem of items) {
        const qty = Number(lineItem.qty) || 0;
        const unit_cost = Number(lineItem.unit_cost) || 0;
        for (let i = 0; i < qty; i++) {
          itemDocs.push({
            product_id: lineItem.product_id,
            product_name: lineItem.product_name || '',
            size: lineItem.size || null,
            sku: lineItem.sku || null,
            inventory_batch_id: batchId,
            purchase_order_id: poId,
            cost_per_pair: unit_cost,
            status: 'available',
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      // Use a transaction for the batch, supplier, PO, and product stock updates
      await db.runTransaction(async (t) => {
        // Create inventory batch
        t.set(batchRef, {
          purchase_order_id: poId,
          supplier_id: supplier_id || null,
          product_id: items[0].product_id || null,
          qty_produced: qty_total,
          qty_passed: qty_total,
          qty_rejected: 0,
          cost_total: Number(total) || 0,
          cost_per_pair: qty_total > 0 ? (Number(total) || 0) / qty_total : 0,
          status: 'complete',
          source: 'purchase_order',
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
          completed_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Update product stock_count per line
        for (const lineItem of items) {
          const qty = Number(lineItem.qty) || 0;
          if (lineItem.product_id && qty > 0) {
            const productRef = db.collection('products').doc(lineItem.product_id);
            t.update(productRef, {
              stock_count: admin.firestore.FieldValue.increment(qty),
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        }

        // Update supplier total_purchased
        if (supplier_id) {
          const supplierRef = db.collection('suppliers').doc(supplier_id);
          t.update(supplierRef, {
            total_purchased: admin.firestore.FieldValue.increment(Number(total) || 0),
            last_order_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // Mark PO as fully received
        t.update(change.after.ref, {
          inventory_batch_id: batchId,
          received_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      // Create inventory_items in batched writes (max 500 per batch)
      const BATCH_SIZE = 400;
      for (let start = 0; start < itemDocs.length; start += BATCH_SIZE) {
        const chunk = itemDocs.slice(start, start + BATCH_SIZE);
        const writeBatch = db.batch();
        for (const doc of chunk) {
          const itemRef = db.collection('inventory_items').doc();
          writeBatch.set(itemRef, doc);
        }
        await writeBatch.commit();
      }

      functions.logger.info(
        `onPurchaseOrderReceived: PO ${poId} received. batch=${batchId} items_created=${qty_total}`
      );

      // Push notification: PO received
      const supplierName = after.supplier_name || 'Supplier';
      await sendToTopic(
        'managers',
        'Purchase Order Received',
        `${supplierName} — ${qty_total} pairs received`,
        { route: `/purchase-orders/${poId}`, type: 'po_received' }
      );

      return null;
    } catch (err) {
      functions.logger.error(`onPurchaseOrderReceived: failed for PO ${poId}`, err);
      throw err;
    }
  });

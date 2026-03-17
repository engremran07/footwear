const functions = require('firebase-functions');
const admin = require('firebase-admin');

/**
 * onCashApproved
 *
 * Trigger: cash_approvals/{approvalId} — onUpdate
 *
 * When a cash_approval status changes to 'approved':
 * 1. Fetch the linked cash_transaction
 * 2. Mark the cash_transaction as 'approved'
 * 3. Update the pnl_snapshot for the transaction's period:
 *    - cash_in  → add to revenue
 *    - cash_out → add to expenses (non-payroll cash outflows)
 * 4. Recalculate net_profit in the snapshot
 *
 * Guards:
 * - Only fires when before.status != 'approved' and after.status == 'approved'
 * - Idempotent: checks cash_transaction.status before updating
 */
exports.onCashApproved = functions.firestore
  .document('cash_approvals/{approvalId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Guard: only fire on transition → approved
    if (before.status === 'approved' || after.status !== 'approved') {
      return null;
    }

    const db = admin.firestore();
    const { approvalId } = context.params;
    const { transaction_id } = after;

    if (!transaction_id) {
      functions.logger.warn(`onCashApproved: no transaction_id on approval ${approvalId}`);
      return null;
    }

    try {
      await db.runTransaction(async (t) => {
        const txRef = db.collection('cash_transactions').doc(transaction_id);
        const txSnap = await t.get(txRef);

        if (!txSnap.exists) {
          functions.logger.warn(`onCashApproved: transaction ${transaction_id} not found`);
          return;
        }

        const tx = txSnap.data();

        // Idempotent: skip if already approved
        if (tx.status === 'approved') {
          functions.logger.info(`onCashApproved: tx ${transaction_id} already approved, skipping`);
          return;
        }

        // Mark transaction approved
        t.update(txRef, {
          status: 'approved',
          approved_by: after.approved_by,
          approved_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Determine P&L period from transaction's created_at
        const createdAt = tx.created_at ? tx.created_at.toDate() : new Date();
        const period = _formatPeriod(createdAt);
        const amount = Number(tx.amount) || 0;

        const snapshotRef = db.collection('pnl_snapshots').doc(period);
        const snapSnap = await t.get(snapshotRef);

        if (tx.type === 'cash_in') {
          if (snapSnap.exists) {
            const snap = snapSnap.data();
            const newRevenue = (snap.revenue || 0) + amount;
            const cogs = snap.cogs || 0;
            const newGrossProfit = newRevenue - cogs;
            const newNetProfit = newGrossProfit - (snap.expenses || 0) - (snap.worker_cost || 0);
            t.update(snapshotRef, {
              revenue: admin.firestore.FieldValue.increment(amount),
              gross_profit: newGrossProfit,
              net_profit: newNetProfit,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
          } else {
            t.set(snapshotRef, {
              period,
              revenue: amount,
              cogs: 0,
              gross_profit: amount,
              expenses: 0,
              worker_cost: 0,
              net_profit: amount,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        } else if (tx.type === 'cash_out') {
          if (snapSnap.exists) {
            const snap = snapSnap.data();
            const newExpenses = (snap.expenses || 0) + amount;
            const newNetProfit = (snap.gross_profit || 0) - newExpenses - (snap.worker_cost || 0);
            t.update(snapshotRef, {
              expenses: admin.firestore.FieldValue.increment(amount),
              net_profit: newNetProfit,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
          } else {
            t.set(snapshotRef, {
              period,
              revenue: 0,
              cogs: 0,
              gross_profit: 0,
              expenses: amount,
              worker_cost: 0,
              net_profit: -amount,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        }
      });

      functions.logger.info(`onCashApproved: processed approval ${approvalId}`);
      return null;
    } catch (err) {
      functions.logger.error(`onCashApproved: failed for approval ${approvalId}`, err);
      throw err;
    }
  });

function _formatPeriod(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

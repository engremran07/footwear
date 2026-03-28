const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { sendToTopic, sendToUser } = require('./notificationHelper');

/**
 * onExpenseApproved
 *
 * Trigger: expense_approvals/{approvalId} — onUpdate
 *
 * When an expense_approval status changes to 'approved':
 * 1. Fetch the linked expense
 * 2. Mark the expense as 'approved'
 * 3. Update pnl_snapshot[period].expenses
 * 4. Recalculate net_profit
 *
 * When status changes to 'rejected':
 * 1. Mark the expense as 'rejected'
 * 2. No P&L update
 */
exports.onExpenseApproved = functions.firestore
  .document('expense_approvals/{approvalId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    const statusChanged = before.status !== after.status;
    const isApproved = after.status === 'approved';
    const isRejected = after.status === 'rejected';

    if (!statusChanged || (!isApproved && !isRejected)) {
      return null;
    }

    const db = admin.firestore();
    const { approvalId } = context.params;
    const { expense_id } = after;

    if (!expense_id) {
      functions.logger.warn(`onExpenseApproved: no expense_id on approval ${approvalId}`);
      return null;
    }

    try {
      const expenseRef = db.collection('expenses').doc(expense_id);

      if (isRejected) {
        await expenseRef.update({
          status: 'rejected',
          rejected_by: after.approved_by || null,
          rejected_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        functions.logger.info(`onExpenseApproved: expense ${expense_id} rejected`);

        // Notify the expense creator about rejection
        const expDoc = await db.collection('expenses').doc(expense_id).get();
        if (expDoc.exists && expDoc.data().created_by) {
          await sendToUser(
            expDoc.data().created_by,
            'Expense Rejected',
            `${after.category || 'Expense'} — ${after.amount || 0} SAR rejected`,
            { route: '/expenses', type: 'expense_rejected' }
          );
        }

        return null;
      }

      // Approved path — use transaction to update expense + pnl_snapshot atomically
      await db.runTransaction(async (t) => {
        const expenseSnap = await t.get(expenseRef);

        if (!expenseSnap.exists) {
          functions.logger.warn(`onExpenseApproved: expense ${expense_id} not found`);
          return;
        }

        const expense = expenseSnap.data();

        // Idempotent: skip if already approved
        if (expense.status === 'approved') {
          functions.logger.info(`onExpenseApproved: expense ${expense_id} already approved`);
          return;
        }

        // Mark expense approved
        t.update(expenseRef, {
          status: 'approved',
          approved_by: after.approved_by,
          approved_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        const createdAt = expense.created_at ? expense.created_at.toDate() : new Date();
        const period = _formatPeriod(createdAt);
        const amount = Number(expense.amount) || 0;

        const snapshotRef = db.collection('pnl_snapshots').doc(period);
        const snapSnap = await t.get(snapshotRef);

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
      });

      functions.logger.info(`onExpenseApproved: processed approval ${approvalId}, expense ${expense_id}`);

      // Push notification: expense approved
      await sendToTopic(
        'managers',
        'Expense Approved',
        `${after.category || 'Expense'} \u2014 ${after.amount || 0} SAR`,
        { route: '/expenses', type: 'expense_approved' }
      );

      return null;
    } catch (err) {
      functions.logger.error(`onExpenseApproved: failed for approval ${approvalId}`, err);
      throw err;
    }
  });

function _formatPeriod(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

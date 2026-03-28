const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { sendToTopic } = require('./notificationHelper');

/**
 * onWorkerPaymentCreated
 *
 * Trigger: worker_payments/{paymentId} — onCreate
 *
 * When a worker payment record is created:
 * 1. Increment workers/{worker_id}.total_earned by payment amount
 * 2. Update pnl_snapshot[period].worker_cost
 * 3. Recalculate net_profit
 * 4. Create a corresponding cash_transaction (cash_out, status=approved)
 *
 * Only processes payments in 'approved' or 'paid' status.
 * Draft/pending payments do NOT affect P&L.
 */
exports.onWorkerPaymentCreated = functions.firestore
  .document('worker_payments/{paymentId}')
  .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const { paymentId } = context.params;
    const payment = snap.data();

    const { worker_id, amount, status, period } = payment;

    // Only process approved/paid payments
    if (!['approved', 'paid'].includes(status)) {
      functions.logger.info(`onWorkerPaymentCreated: payment ${paymentId} in status=${status}, skipping P&L update`);
      return null;
    }

    if (!worker_id || !amount || !period) {
      functions.logger.warn(`onWorkerPaymentCreated: missing fields on payment ${paymentId}`);
      return null;
    }

    const numAmount = Number(amount) || 0;
    if (numAmount <= 0) {
      functions.logger.warn(`onWorkerPaymentCreated: zero/negative amount on payment ${paymentId}`);
      return null;
    }

    try {
      await db.runTransaction(async (t) => {
        // Update worker total_earned
        const workerRef = db.collection('workers').doc(worker_id);
        const workerSnap = await t.get(workerRef);

        if (workerSnap.exists) {
          t.update(workerRef, {
            total_earned: admin.firestore.FieldValue.increment(numAmount),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // Update pnl_snapshot worker_cost
        const snapshotRef = db.collection('pnl_snapshots').doc(period);
        const snapSnap = await t.get(snapshotRef);

        if (snapSnap.exists) {
          const snap = snapSnap.data();
          const newWorkerCost = (snap.worker_cost || 0) + numAmount;
          const newNetProfit = (snap.gross_profit || 0) - (snap.expenses || 0) - newWorkerCost;
          t.update(snapshotRef, {
            worker_cost: admin.firestore.FieldValue.increment(numAmount),
            net_profit: newNetProfit,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          t.set(snapshotRef, {
            period,
            revenue: 0,
            cogs: 0,
            gross_profit: 0,
            expenses: 0,
            worker_cost: numAmount,
            net_profit: -numAmount,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // Create corresponding cash_transaction
        const txRef = db.collection('cash_transactions').doc();
        t.set(txRef, {
          type: 'cash_out',
          amount: numAmount,
          reference: `worker_payment:${paymentId}`,
          pnl_category: 'worker_cost',
          worker_id,
          worker_payment_id: paymentId,
          status: 'approved',
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      functions.logger.info(`onWorkerPaymentCreated: processed payment ${paymentId} for worker ${worker_id}`);

      // Push notification to admins: worker payment created
      const workerName = payment.worker_name || 'Worker';
      const amount = payment.amount || 0;
      await sendToTopic(
        'admins',
        'Worker Payment Created',
        `${workerName} — ${amount} SAR`,
        { route: '/workers', type: 'worker_payment' }
      );

      return null;
    } catch (err) {
      functions.logger.error(`onWorkerPaymentCreated: failed for payment ${paymentId}`, err);
      throw err;
    }
  });

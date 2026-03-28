const admin = require('firebase-admin');
admin.initializeApp();

// Export all 9 Cloud Functions
const { onOrderCreated }             = require('./src/onOrderCreated');
const { onOrderItemAdded }           = require('./src/onOrderItemAdded');
const { onCashApproved }             = require('./src/onCashApproved');
const { onExpenseApproved }          = require('./src/onExpenseApproved');
const { onWorkerPaymentCreated }     = require('./src/onWorkerPaymentCreated');
const { onQCReject }                 = require('./src/onQCReject');
const { onInventoryBatchComplete }   = require('./src/onInventoryBatchComplete');
const { onPurchaseOrderReceived }    = require('./src/onPurchaseOrderReceived');
const { onReturnApproved }           = require('./src/onReturnApproved');
const { manageUserAuth }             = require('./src/manageUserAuth');

module.exports = {
  onOrderCreated,
  onOrderItemAdded,
  onCashApproved,
  onExpenseApproved,
  onWorkerPaymentCreated,
  onQCReject,
  onInventoryBatchComplete,
  onPurchaseOrderReceived,
  onReturnApproved,
  manageUserAuth,
};

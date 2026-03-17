/**
 * seed_data.js
 * Populates Firestore with realistic business data for Footwear ERP.
 * Run: node seed_data.js
 * Requires: seed_admin.js to have been run first.
 */

'use strict';
const https = require('https');

const API_KEY    = 'AIzaSyAVT31GIOQ01IV4O1K7a7ysRhB8PEfQJXY';
const PROJECT_ID = 'footwear-erp-a3e63';
const ADMIN_EMAIL = 'admin@footwear.erp';
const ADMIN_PASS  = 'Admin@12345!';
const ADMIN_UID   = 'vWDGOpLgVfYvSuOOWA3lkTitWgI2';

// ──────────────────────────────────────────────────────────────
// Firestore value helpers
// ──────────────────────────────────────────────────────────────
class Dbl { constructor(v) { this.v = Number(v); } }
class Ts  { constructor(d) { this.d = d instanceof Date ? d : new Date(d); } }
const d  = (v) => new Dbl(v);      // force doubleValue
const ts = (date) => new Ts(date);  // Firestore timestamp
const NOW = () => ts(new Date());

function fsVal(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Dbl) return { doubleValue: v.v };
  if (v instanceof Ts)  return { timestampValue: v.d.toISOString() };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'string')  return { stringValue: v };
  if (typeof v === 'number')  return { integerValue: String(v) };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(fsVal) } };
  if (typeof v === 'object')  return { mapValue: { fields: fsFields(v) } };
  throw new Error(`Unknown type: ${typeof v} for ${v}`);
}
function fsFields(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v !== undefined) out[k] = fsVal(v);
  }
  return out;
}

// ──────────────────────────────────────────────────────────────
// HTTP helpers
// ──────────────────────────────────────────────────────────────
function post(hostname, path, body, token) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const headers = { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) };
    if (token) headers['Authorization'] = `Bearer ${token}`;
    const req = https.request({ hostname, path, method: 'POST', headers }, res => {
      let raw = '';
      res.on('data', c => raw += c);
      res.on('end', () => { try { resolve({ status: res.statusCode, body: JSON.parse(raw) }); } catch { resolve({ status: res.statusCode, body: raw }); } });
    });
    req.on('error', reject);
    req.write(data); req.end();
  });
}

function fsWrite(docPath, fields, token) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ fields });
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body),
      'Authorization': `Bearer ${token}`,
    };
    const path = `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${docPath}`;
    const req = https.request({ hostname: 'firestore.googleapis.com', path, method: 'PATCH', headers }, res => {
      let raw = '';
      res.on('data', c => raw += c);
      res.on('end', () => { try { resolve({ status: res.statusCode, body: JSON.parse(raw) }); } catch { resolve({ status: res.statusCode, body: raw }); } });
    });
    req.on('error', reject);
    req.write(body); req.end();
  });
}

async function write(collection, id, data, token) {
  const fields = fsFields(data);
  const res = await fsWrite(`${collection}/${id}`, fields, token);
  if (res.status === 200 || res.status === 201) {
    process.stdout.write(`  ✓ ${collection}/${id}\n`);
  } else {
    const err = res.body?.error?.message || JSON.stringify(res.body);
    console.warn(`  ✗ ${collection}/${id} [${res.status}]: ${err}`);
  }
  return res;
}

async function writeAll(collection, docs, token) {
  for (const [id, data] of Object.entries(docs)) {
    await write(collection, id, data, token);
  }
}

// ──────────────────────────────────────────────────────────────
// Date constants
// ──────────────────────────────────────────────────────────────
const D = {
  feb01: new Date('2026-02-01T08:00:00Z'),
  feb10: new Date('2026-02-10T08:00:00Z'),
  feb15: new Date('2026-02-15T08:00:00Z'),
  feb20: new Date('2026-02-20T08:00:00Z'),
  feb25: new Date('2026-02-25T08:00:00Z'),
  mar01: new Date('2026-03-01T08:00:00Z'),
  mar03: new Date('2026-03-03T08:00:00Z'),
  mar05: new Date('2026-03-05T08:00:00Z'),
  mar08: new Date('2026-03-08T08:00:00Z'),
  mar10: new Date('2026-03-10T08:00:00Z'),
  mar12: new Date('2026-03-12T08:00:00Z'),
  mar14: new Date('2026-03-14T08:00:00Z'),
  mar15: new Date('2026-03-15T08:00:00Z'),
  now:   new Date(),
};

// ──────────────────────────────────────────────────────────────
// Seed data definitions
// ──────────────────────────────────────────────────────────────

const PRODUCTS = {
  'prod-001': {
    sku: 'FSH-OXFD-01', name: 'Classic Oxford', category: 'Formal',
    sizes: ['39', '40', '41', '42', '43', '44'],
    cost_price: d(85), sell_price: d(145), stock_count: 8, active: true,
    created_at: ts(D.feb01), updated_at: ts(D.feb01),
  },
  'prod-002': {
    sku: 'FSH-SPRT-02', name: 'Sports Runner Pro', category: 'Sports',
    sizes: ['38', '39', '40', '41', '42', '43', '44'],
    cost_price: d(65), sell_price: d(115), stock_count: 8, active: true,
    created_at: ts(D.feb01), updated_at: ts(D.feb01),
  },
  'prod-003': {
    sku: 'FSH-LOAF-03', name: 'Casual Loafer', category: 'Casual',
    sizes: ['39', '40', '41', '42', '43'],
    cost_price: d(55), sell_price: d(95), stock_count: 0, active: true,
    created_at: ts(D.feb10), updated_at: ts(D.feb10),
  },
  'prod-004': {
    sku: 'FSH-BOOT-04', name: 'Desert Leather Boot', category: 'Boots',
    sizes: ['40', '41', '42', '43', '44', '45'],
    cost_price: d(110), sell_price: d(185), stock_count: 0, active: true,
    created_at: ts(D.feb10), updated_at: ts(D.feb10),
  },
  'prod-005': {
    sku: 'FSH-SNDL-05', name: 'Summer Sandal', category: 'Sandals',
    sizes: ['38', '39', '40', '41', '42', '43', '44'],
    cost_price: d(35), sell_price: d(65), stock_count: 0, active: true,
    created_at: ts(D.feb15), updated_at: ts(D.feb15),
  },
  'prod-006': {
    sku: 'FSH-EXEC-06', name: 'Executive Derby', category: 'Formal',
    sizes: ['39', '40', '41', '42', '43', '44'],
    cost_price: d(95), sell_price: d(160), stock_count: 0, active: true,
    created_at: ts(D.feb15), updated_at: ts(D.feb15),
  },
};

const SUPPLIERS = {
  'supp-001': {
    name: 'Al-Farooq Leather Works',
    contact_name: 'Farooq Ahmed',
    phone: '+92 42 3570 1234',
    email: 'farooq.leather@gmail.com',
    address: 'D-12 Quaid-e-Azam Industrial Estate, Lahore',
    payment_terms: 'Net 30',
    total_purchased: d(68500),
    last_order_at: ts(D.mar01),
    active: true,
    created_at: ts(D.feb01), updated_at: ts(D.mar01),
  },
  'supp-002': {
    name: 'Punjab Sole Industries',
    contact_name: 'Tariq Mehmood',
    phone: '+92 52 3254 7890',
    email: 'tariqmehmood@punjabsole.pk',
    address: 'Block 4, Sialkot Export Processing Zone',
    payment_terms: 'Net 45',
    total_purchased: d(39200),
    last_order_at: ts(D.feb20),
    active: true,
    created_at: ts(D.feb01), updated_at: ts(D.feb20),
  },
};

const CUSTOMERS = {
  'cust-001': {
    name: 'Al-Madinah Shoes Trading',
    phone: '+966 11 234 5678',
    email: 'orders@almadinah-shoes.sa',
    address: 'King Fahd Rd, Olaya District',
    city: 'Riyadh', country: 'Saudi Arabia',
    balance: d(0), total_orders: 3,
    created_at: ts(D.feb01), updated_at: ts(D.mar10),
  },
  'cust-002': {
    name: 'Jeddah Footwear Distributors',
    phone: '+966 12 665 9900',
    email: 'purchasing@jfd.sa',
    address: 'Al-Balad Commercial Zone',
    city: 'Jeddah', country: 'Saudi Arabia',
    balance: d(870), total_orders: 2,
    created_at: ts(D.feb05 || D.feb10), updated_at: ts(D.mar08),
  },
  'cust-003': {
    name: 'Gulf Style Retail LLC',
    phone: '+966 13 812 4455',
    email: 'info@gulfstyle.sa',
    address: 'Dhahran Street, Malik Commercial Tower',
    city: 'Dammam', country: 'Saudi Arabia',
    balance: d(0), total_orders: 1,
    created_at: ts(D.feb20), updated_at: ts(D.mar05),
  },
  'cust-004': {
    name: 'Al-Noor Fashion House',
    phone: '+966 12 556 7712',
    email: null,
    address: 'Ibrahim Al-Khalil Rd, Commercial District',
    city: 'Mecca', country: 'Saudi Arabia',
    balance: d(1920), total_orders: 1,
    created_at: ts(D.mar01), updated_at: ts(D.mar10),
  },
  'cust-005': {
    name: 'Desert King Shoes',
    phone: '+966 12 789 1133',
    email: 'desertking@hotmail.com',
    address: 'Tahlia Street, Zahra Mall',
    city: 'Jeddah', country: 'Saudi Arabia',
    balance: d(0), total_orders: 0,
    created_at: ts(D.mar05), updated_at: ts(D.mar05),
  },
  'cust-006': {
    name: 'Riyadh Wholesale Trading Co.',
    phone: '+966 11 478 2255',
    email: 'rwt@buynow.sa',
    address: 'Industrial Area, 2nd Ring Road',
    city: 'Riyadh', country: 'Saudi Arabia',
    balance: d(0), total_orders: 2,
    created_at: ts(D.feb10), updated_at: ts(D.mar12),
  },
  'cust-007': {
    name: 'Eastern Province Traders',
    phone: '+966 13 864 0011',
    email: 'ept.khobar@gmail.com',
    address: 'Prince Bandar Street, Al-Ulaya',
    city: 'Al-Khobar', country: 'Saudi Arabia',
    balance: d(0), total_orders: 1,
    created_at: ts(D.feb15), updated_at: ts(D.mar12),
  },
  'cust-008': {
    name: 'National Shoe Gallery',
    phone: '+966 11 533 8844',
    email: null,
    address: 'Panorama Mall, King Fahd District',
    city: 'Riyadh', country: 'Saudi Arabia',
    balance: d(0), total_orders: 0,
    created_at: ts(D.mar10), updated_at: ts(D.mar10),
  },
};

const WORKERS = {
  'wkr-pk-001': {
    name: 'Muhammad Tariq Khan', type: 'pk', rate_per_pair: d(85), currency: 'PKR',
    total_earned: d(40800), pairs_produced: 480, active: true,
    joined_at: ts(D.feb01), created_at: ts(D.feb01), updated_at: ts(D.mar15),
  },
  'wkr-pk-002': {
    name: 'Ahmed Raza Siddiqui', type: 'pk', rate_per_pair: d(90), currency: 'PKR',
    total_earned: d(32400), pairs_produced: 360, active: true,
    joined_at: ts(D.feb01), created_at: ts(D.feb01), updated_at: ts(D.mar15),
  },
  'wkr-pk-003': {
    name: 'Shahid Hussain', type: 'pk', rate_per_pair: d(80), currency: 'PKR',
    total_earned: d(19200), pairs_produced: 240, active: true,
    joined_at: ts(D.feb10), created_at: ts(D.feb10), updated_at: ts(D.mar15),
  },
  'wkr-pk-004': {
    name: 'Imran Ali Bhatti', type: 'pk', rate_per_pair: d(85), currency: 'PKR',
    total_earned: d(40800), pairs_produced: 480, active: true,
    joined_at: ts(D.feb01), created_at: ts(D.feb01), updated_at: ts(D.mar15),
  },
  'wkr-ksa-001': {
    name: 'Abdullah Al-Rashidi', type: 'ksa', rate_per_pair: d(15), currency: 'SAR',
    total_earned: d(12000), pairs_produced: 800, active: true,
    joined_at: ts(D.feb01), created_at: ts(D.feb01), updated_at: ts(D.mar15),
  },
  'wkr-ksa-002': {
    name: 'Faisal Al-Harbi', type: 'ksa', rate_per_pair: d(15), currency: 'SAR',
    total_earned: d(11250), pairs_produced: 750, active: true,
    joined_at: ts(D.feb01), created_at: ts(D.feb01), updated_at: ts(D.mar15),
  },
  'wkr-ksa-003': {
    name: 'Omar Al-Ghamdi', type: 'ksa', rate_per_pair: d(12), currency: 'SAR',
    total_earned: d(7200), pairs_produced: 600, active: true,
    joined_at: ts(D.feb10), created_at: ts(D.feb10), updated_at: ts(D.mar15),
  },
};

const INV_BATCHES = {
  'batch-001': {
    product_id: 'prod-001', purchase_order_id: null, supplier_id: null,
    qty_produced: 20, qty_passed: 18, qty_rejected: 2,
    cost_total: d(1700), cost_per_pair: d(94.44),
    status: 'complete', source: 'production',
    last_qc_id: 'qc-001',
    completed_at: ts(D.feb25),
    created_at: ts(D.feb20), updated_at: ts(D.feb25),
  },
  'batch-002': {
    product_id: 'prod-002', purchase_order_id: null, supplier_id: null,
    qty_produced: 20, qty_passed: 20, qty_rejected: 0,
    cost_total: d(1300), cost_per_pair: d(65),
    status: 'complete', source: 'production',
    last_qc_id: null,
    completed_at: ts(D.mar05),
    created_at: ts(D.mar01), updated_at: ts(D.mar05),
  },
  'batch-003': {
    product_id: 'prod-004', purchase_order_id: null, supplier_id: null,
    qty_produced: 12, qty_passed: 0, qty_rejected: 0,
    cost_total: d(1320), cost_per_pair: d(0),
    status: 'in_production', source: 'production',
    last_qc_id: null, completed_at: null,
    created_at: ts(D.mar12), updated_at: ts(D.mar12),
  },
  'batch-004': {
    product_id: 'prod-003', purchase_order_id: null, supplier_id: null,
    qty_produced: 24, qty_passed: 24, qty_rejected: 0,
    cost_total: d(1320), cost_per_pair: d(55),
    status: 'qc_pending', source: 'production',
    last_qc_id: null, completed_at: null,
    created_at: ts(D.mar14), updated_at: ts(D.mar14),
  },
};

// inventory_items — batch-001 (Classic Oxford, prod-001)
// 4 sold (order-001), 6 reserved (order-002), 8 available
function buildInvItems(batchId, productId, productName, sku, costPerPair, sizeQtyMap, statusMap) {
  const items = {};
  let counter = 0;
  for (const [size, quantities] of Object.entries(sizeQtyMap)) {
    for (const [status, qty] of Object.entries(quantities)) {
      for (let i = 0; i < qty; i++) {
        counter++;
        const id = `inv-${batchId}-${String(counter).padStart(3, '0')}`;
        items[id] = {
          product_id: productId, product_name: productName, sku,
          size, inventory_batch_id: batchId, purchase_order_id: null,
          cost_per_pair: d(costPerPair),
          status,
          order_id: statusMap[status]?.order_id ?? null,
          order_item_id: statusMap[status]?.order_item_id ?? null,
          qc_record_id: batchId === 'batch-001' ? 'qc-001' : null,
          reserved_at: status === 'reserved' ? ts(D.mar08) : null,
          created_at: ts(batchId === 'batch-001' ? D.feb25 : D.mar05),
          updated_at: ts(batchId === 'batch-001' ? D.feb25 : D.mar05),
        };
      }
    }
  }
  return items;
}

const INV_ITEMS_B001 = buildInvItems('batch-001', 'prod-001', 'Classic Oxford', 'FSH-OXFD-01', 94.44, {
  '40': { sold: 1, available: 2 },
  '41': { sold: 1, reserved: 2, available: 1 },
  '42': { sold: 1, reserved: 2, available: 2 },
  '43': { sold: 1, reserved: 2, available: 2 },
  '44': { available: 1 },
}, {
  sold:     { order_id: 'order-001', order_item_id: 'oitem-001' },
  reserved: { order_id: 'order-002', order_item_id: 'oitem-003' },
});

const INV_ITEMS_B002 = buildInvItems('batch-002', 'prod-002', 'Sports Runner Pro', 'FSH-SPRT-02', 65, {
  '39': { sold: 1, available: 2 },
  '40': { sold: 1, reserved: 2, available: 1 },
  '41': { sold: 1, reserved: 2, available: 2 },
  '42': { sold: 1, reserved: 2, available: 2 },
  '43': { available: 1 },
}, {
  sold:     { order_id: 'order-001', order_item_id: 'oitem-002' },
  reserved: { order_id: 'order-003', order_item_id: 'oitem-004' },
});

const ALL_INV_ITEMS = { ...INV_ITEMS_B001, ...INV_ITEMS_B002 };

const ORDERS = {
  'order-001': {
    customer_id: 'cust-001', customer_name: 'Al-Madinah Shoes Trading',
    status: 'delivered', total: d(1040),
    notes: 'First order — 12 dozen mixed styles',
    created_by: ADMIN_UID,
    created_at: ts(D.mar01), updated_at: ts(D.mar10),
  },
  'order-002': {
    customer_id: 'cust-002', customer_name: 'Jeddah Footwear Distributors',
    status: 'processing', total: d(870),
    notes: 'Oxford restocking order',
    created_by: ADMIN_UID,
    created_at: ts(D.mar08), updated_at: ts(D.mar08),
  },
  'order-003': {
    customer_id: 'cust-003', customer_name: 'Gulf Style Retail LLC',
    status: 'processing', total: d(920),
    notes: null,
    created_by: ADMIN_UID,
    created_at: ts(D.mar08), updated_at: ts(D.mar08),
  },
  'order-004': {
    customer_id: 'cust-004', customer_name: 'Al-Noor Fashion House',
    status: 'pending', total: d(1920),
    notes: 'Executive Derby — Ramadan collection',
    created_by: ADMIN_UID,
    created_at: ts(D.mar10), updated_at: ts(D.mar10),
  },
  'order-005': {
    customer_id: 'cust-006', customer_name: 'Riyadh Wholesale Trading Co.',
    status: 'shipped', total: d(2280),
    notes: 'Casual loafer bulk order — 20 dozen',
    created_by: ADMIN_UID,
    created_at: ts(D.mar05), updated_at: ts(D.mar12),
  },
  'order-006': {
    customer_id: 'cust-001', customer_name: 'Al-Madinah Shoes Trading',
    status: 'delivered', total: d(1380),
    notes: null,
    created_by: ADMIN_UID,
    created_at: ts(D.mar03), updated_at: ts(D.mar12),
  },
};

const ORDER_ITEMS = {
  'oitem-001': {
    order_id: 'order-001', product_id: 'prod-001', product_name: 'Classic Oxford',
    size: '41', qty: 4, unit_price: d(145), subtotal: d(580),
    inventory_batch_id: 'batch-001',
    status: 'dispatched',
    created_at: ts(D.mar01), updated_at: ts(D.mar10),
  },
  'oitem-002': {
    order_id: 'order-001', product_id: 'prod-002', product_name: 'Sports Runner Pro',
    size: '40', qty: 4, unit_price: d(115), subtotal: d(460),
    inventory_batch_id: 'batch-002',
    status: 'dispatched',
    created_at: ts(D.mar01), updated_at: ts(D.mar10),
  },
  'oitem-003': {
    order_id: 'order-002', product_id: 'prod-001', product_name: 'Classic Oxford',
    size: '42', qty: 6, unit_price: d(145), subtotal: d(870),
    inventory_batch_id: 'batch-001',
    status: 'reserved',
    created_at: ts(D.mar08), updated_at: ts(D.mar08),
  },
  'oitem-004': {
    order_id: 'order-003', product_id: 'prod-002', product_name: 'Sports Runner Pro',
    size: '41', qty: 8, unit_price: d(115), subtotal: d(920),
    inventory_batch_id: 'batch-002',
    status: 'reserved',
    created_at: ts(D.mar08), updated_at: ts(D.mar08),
  },
  'oitem-005': {
    order_id: 'order-004', product_id: 'prod-006', product_name: 'Executive Derby',
    size: '42', qty: 12, unit_price: d(160), subtotal: d(1920),
    inventory_batch_id: null,
    status: 'pending',
    created_at: ts(D.mar10), updated_at: ts(D.mar10),
  },
  'oitem-006': {
    order_id: 'order-005', product_id: 'prod-003', product_name: 'Casual Loafer',
    size: '41', qty: 24, unit_price: d(95), subtotal: d(2280),
    inventory_batch_id: null,
    status: 'dispatched',
    created_at: ts(D.mar05), updated_at: ts(D.mar12),
  },
  'oitem-007': {
    order_id: 'order-006', product_id: 'prod-002', product_name: 'Sports Runner Pro',
    size: '39', qty: 12, unit_price: d(115), subtotal: d(1380),
    inventory_batch_id: 'batch-002',
    status: 'dispatched',
    created_at: ts(D.mar03), updated_at: ts(D.mar12),
  },
};

const EXPENSES = {
  'exp-001': {
    category: 'rent', amount: d(15000),
    description: 'Monthly warehouse rent — Riyadh Industrial Zone',
    receipt_url: null, status: 'approved',
    created_by: ADMIN_UID, approved_by: ADMIN_UID,
    approved_at: ts(D.feb15), rejected_by: null, rejected_at: null,
    created_at: ts(D.feb10), updated_at: ts(D.feb15),
  },
  'exp-002': {
    category: 'utilities', amount: d(3200),
    description: 'Electricity and cooling — KSA warehouse Feb 2026',
    receipt_url: null, status: 'approved',
    created_by: ADMIN_UID, approved_by: ADMIN_UID,
    approved_at: ts(D.feb20), rejected_by: null, rejected_at: null,
    created_at: ts(D.feb15), updated_at: ts(D.feb20),
  },
  'exp-003': {
    category: 'transport', amount: d(4800),
    description: 'Cargo freight — Lahore to Riyadh, 240 pairs',
    receipt_url: null, status: 'approved',
    created_by: ADMIN_UID, approved_by: ADMIN_UID,
    approved_at: ts(D.mar03), rejected_by: null, rejected_at: null,
    created_at: ts(D.mar01), updated_at: ts(D.mar03),
  },
  'exp-004': {
    category: 'marketing', amount: d(7500),
    description: 'Digital marketing campaign — Q1 2026',
    receipt_url: null, status: 'pending_approval',
    created_by: ADMIN_UID, approved_by: null,
    approved_at: null, rejected_by: null, rejected_at: null,
    created_at: ts(D.mar12), updated_at: ts(D.mar12),
  },
  'exp-005': {
    category: 'other', amount: d(1200),
    description: 'Office supplies and stationery',
    receipt_url: null, status: 'draft',
    created_by: ADMIN_UID, approved_by: null,
    approved_at: null, rejected_by: null, rejected_at: null,
    created_at: ts(D.mar14), updated_at: ts(D.mar14),
  },
};

const EXPENSE_APPROVALS = {
  'eapp-001': {
    expense_id: 'exp-001', amount: d(15000), category: 'rent',
    description: 'Monthly warehouse rent — Riyadh Industrial Zone',
    status: 'approved', approved_by: ADMIN_UID,
    notes: 'Recurring monthly expense',
    created_at: ts(D.feb10), updated_at: ts(D.feb15),
  },
  'eapp-002': {
    expense_id: 'exp-002', amount: d(3200), category: 'utilities',
    description: 'Electricity and cooling — KSA warehouse Feb 2026',
    status: 'approved', approved_by: ADMIN_UID,
    notes: null,
    created_at: ts(D.feb15), updated_at: ts(D.feb20),
  },
  'eapp-003': {
    expense_id: 'exp-004', amount: d(7500), category: 'marketing',
    description: 'Digital marketing campaign — Q1 2026',
    status: 'pending', approved_by: null,
    notes: null,
    created_at: ts(D.mar12), updated_at: ts(D.mar12),
  },
};

const WORKER_PAYMENTS = {
  'wpay-001': {
    worker_id: 'wkr-pk-001', worker_name: 'Muhammad Tariq Khan', worker_type: 'pk',
    amount: d(10200), pairs_count: 120, period: '2026-02',
    status: 'paid', approved_by: ADMIN_UID, approved_at: ts(D.mar01),
    notes: 'February production batch — Oxford and Sports Runner',
    created_at: ts(D.feb25), updated_at: ts(D.mar01),
  },
  'wpay-002': {
    worker_id: 'wkr-pk-002', worker_name: 'Ahmed Raza Siddiqui', worker_type: 'pk',
    amount: d(10800), pairs_count: 120, period: '2026-02',
    status: 'paid', approved_by: ADMIN_UID, approved_at: ts(D.mar01),
    notes: 'February production batch',
    created_at: ts(D.feb25), updated_at: ts(D.mar01),
  },
  'wpay-003': {
    worker_id: 'wkr-ksa-001', worker_name: 'Abdullah Al-Rashidi', worker_type: 'ksa',
    amount: d(3000), pairs_count: 200, period: '2026-02',
    status: 'paid', approved_by: ADMIN_UID, approved_at: ts(D.mar03),
    notes: 'Dispatch and warehouse operations',
    created_at: ts(D.feb25), updated_at: ts(D.mar03),
  },
  'wpay-004': {
    worker_id: 'wkr-pk-001', worker_name: 'Muhammad Tariq Khan', worker_type: 'pk',
    amount: d(7650), pairs_count: 90, period: '2026-03',
    status: 'pending', approved_by: null, approved_at: null,
    notes: 'March production — in progress',
    created_at: ts(D.mar14), updated_at: ts(D.mar14),
  },
};

const PURCHASE_ORDERS = {
  'po-001': {
    supplier_id: 'supp-001', supplier_name: 'Al-Farooq Leather Works',
    items: [
      { product_id: 'prod-001', product_name: 'Classic Oxford', sku: 'FSH-OXFD-01', size: '41', qty: 120, unit_cost: d(62) },
      { product_id: 'prod-001', product_name: 'Classic Oxford', sku: 'FSH-OXFD-01', size: '42', qty: 120, unit_cost: d(62) },
    ],
    total: d(14880), status: 'received',
    expected_delivery: ts(D.mar01),
    inventory_batch_id: 'batch-001',
    received_at: ts(D.feb25),
    notes: 'Full grain leather uppers — Lahore tannery',
    created_by: ADMIN_UID,
    created_at: ts(D.feb10), updated_at: ts(D.feb25),
  },
  'po-002': {
    supplier_id: 'supp-002', supplier_name: 'Punjab Sole Industries',
    items: [
      { product_id: 'prod-002', product_name: 'Sports Runner Pro', sku: 'FSH-SPRT-02', size: '40', qty: 240, unit_cost: d(48) },
    ],
    total: d(11520), status: 'sent',
    expected_delivery: ts(D.mar15),
    inventory_batch_id: null,
    received_at: null,
    notes: 'EVA foam soles — rubber outsole for sports line',
    created_by: ADMIN_UID,
    created_at: ts(D.feb20), updated_at: ts(D.feb20),
  },
};

const CASH_TRANSACTIONS = {
  'cash-001': {
    type: 'cash_in', amount: d(1040),
    reference: 'Order order-001 — Al-Madinah Shoes',
    pnl_category: 'revenue',
    description: 'Payment received for Classic Oxford + Sports Runner',
    worker_id: null, worker_payment_id: null,
    status: 'approved', approved_by: ADMIN_UID, approved_at: ts(D.mar10),
    created_at: ts(D.mar10), updated_at: ts(D.mar10),
  },
  'cash-002': {
    type: 'cash_in', amount: d(1380),
    reference: 'Order order-006 — Al-Madinah Shoes',
    pnl_category: 'revenue',
    description: 'Sports Runner Pro — 12 dozen, delivery confirmed',
    worker_id: null, worker_payment_id: null,
    status: 'approved', approved_by: ADMIN_UID, approved_at: ts(D.mar12),
    created_at: ts(D.mar12), updated_at: ts(D.mar12),
  },
  'cash-003': {
    type: 'cash_out', amount: d(15000),
    reference: 'Expense exp-001 — Warehouse Rent',
    pnl_category: 'expenses',
    description: 'Monthly warehouse rent payment — Feb 2026',
    worker_id: null, worker_payment_id: null,
    status: 'approved', approved_by: ADMIN_UID, approved_at: ts(D.feb15),
    created_at: ts(D.feb15), updated_at: ts(D.feb15),
  },
  'cash-004': {
    type: 'cash_in', amount: d(870),
    reference: 'Order order-002 advance — Jeddah Footwear',
    pnl_category: 'revenue',
    description: '50% advance payment for Oxford restocking',
    worker_id: null, worker_payment_id: null,
    status: 'pending', approved_by: null, approved_at: null,
    created_at: ts(D.mar15), updated_at: ts(D.mar15),
  },
};

const CASH_APPROVALS = {
  'capp-001': {
    transaction_id: 'cash-001', amount: d(1040), type: 'cash_in',
    reference: 'Order order-001 — Al-Madinah Shoes',
    status: 'approved', approved_by: ADMIN_UID,
    notes: null, created_at: ts(D.mar10), updated_at: ts(D.mar10),
  },
  'capp-002': {
    transaction_id: 'cash-002', amount: d(1380), type: 'cash_in',
    reference: 'Order order-006 — Al-Madinah Shoes',
    status: 'approved', approved_by: ADMIN_UID,
    notes: null, created_at: ts(D.mar12), updated_at: ts(D.mar12),
  },
  'capp-003': {
    transaction_id: 'cash-004', amount: d(870), type: 'cash_in',
    reference: 'Order order-002 advance — Jeddah Footwear',
    status: 'pending', approved_by: null,
    notes: null, created_at: ts(D.mar15), updated_at: ts(D.mar15),
  },
};

const QC_RECORDS = {
  'qc-001': {
    batch_id: 'batch-001', product_id: 'prod-001',
    passed_qty: 18, rejected_qty: 2,
    worker_id: 'wkr-pk-001',
    rejected_items: [
      { inventory_item_id: '', size: '40', reason: 'stitching_issue' },
      { inventory_item_id: '', size: '43', reason: 'sole_defect' },
    ],
    notes: 'Minor stitching loose on heel counter — rejected 2 pairs',
    inspector: ADMIN_UID,
    created_at: ts(D.feb25),
  },
};

const WASTE_RECORDS = {
  'waste-001': {
    qc_record_id: 'qc-001', batch_id: 'batch-001', product_id: 'prod-001',
    size: '40', inventory_item_id: null, worker_id: 'wkr-pk-001',
    reason: 'stitching_issue', disposed: false, disposed_at: null,
    created_at: ts(D.feb25),
  },
  'waste-002': {
    qc_record_id: 'qc-001', batch_id: 'batch-001', product_id: 'prod-001',
    size: '43', inventory_item_id: null, worker_id: 'wkr-pk-001',
    reason: 'sole_defect', disposed: false, disposed_at: null,
    created_at: ts(D.feb25),
  },
};

const SETTINGS_UPDATE = {
  company_address: 'Industrial Zone, 2nd Ring Road, Riyadh, KSA',
  company_phone: '+966 11 234 5678',
  default_pk_rate: d(85),
  default_ksa_rate: d(15),
  product_categories: ['Formal', 'Casual', 'Sports', 'Boots', 'Sandals', 'Kids', 'Safety'],
  expense_categories: ['rent', 'utilities', 'transport', 'marketing', 'materials', 'other'],
  qc_reject_reasons: ['stitching_issue', 'sole_defect', 'size_mismatch', 'cosmetic_damage', 'material_defect', 'wrong_color', 'other'],
};

// ──────────────────────────────────────────────────────────────
// Main
// ──────────────────────────────────────────────────────────────
async function main() {
  console.log('=== Footwear ERP Data Seed ===\n');

  // Sign in
  process.stdout.write(`Signing in as ${ADMIN_EMAIL}...\n`);
  const signInRes = await post('identitytoolkit.googleapis.com',
    `/v1/accounts:signInWithPassword?key=${API_KEY}`,
    { email: ADMIN_EMAIL, password: ADMIN_PASS, returnSecureToken: true }
  );
  if (signInRes.status !== 200) {
    console.error('Sign-in failed:', signInRes.body?.error?.message);
    process.exit(1);
  }
  const token = signInRes.body.idToken;
  console.log('  Signed in ✓\n');

  console.log('→ Products');
  await writeAll('products', PRODUCTS, token);

  console.log('\n→ Suppliers');
  await writeAll('suppliers', SUPPLIERS, token);

  console.log('\n→ Customers');
  await writeAll('customers', CUSTOMERS, token);

  console.log('\n→ Workers');
  await writeAll('workers', WORKERS, token);

  console.log('\n→ Inventory Batches');
  await writeAll('inventory_batches', INV_BATCHES, token);

  console.log('\n→ Inventory Items');
  await writeAll('inventory_items', ALL_INV_ITEMS, token);

  console.log('\n→ Orders');
  await writeAll('orders', ORDERS, token);

  console.log('\n→ Order Items');
  await writeAll('order_items', ORDER_ITEMS, token);

  console.log('\n→ Expenses');
  await writeAll('expenses', EXPENSES, token);

  console.log('\n→ Expense Approvals');
  await writeAll('expense_approvals', EXPENSE_APPROVALS, token);

  console.log('\n→ Worker Payments');
  await writeAll('worker_payments', WORKER_PAYMENTS, token);

  console.log('\n→ Purchase Orders');
  await writeAll('purchase_orders', PURCHASE_ORDERS, token);

  console.log('\n→ Cash Transactions');
  await writeAll('cash_transactions', CASH_TRANSACTIONS, token);

  console.log('\n→ Cash Approvals');
  await writeAll('cash_approvals', CASH_APPROVALS, token);

  console.log('\n→ QC Records');
  await writeAll('qc_records', QC_RECORDS, token);

  console.log('\n→ Waste Records');
  await writeAll('waste_records', WASTE_RECORDS, token);

  console.log('\n→ Settings (update with admin panel config)');
  await write('settings', 'global', {
    ...SETTINGS_UPDATE,
    updated_at: ts(D.now),
  }, token);

  console.log('\n=== Seed complete ===');
  console.log(`  Products:          ${Object.keys(PRODUCTS).length}`);
  console.log(`  Suppliers:         ${Object.keys(SUPPLIERS).length}`);
  console.log(`  Customers:         ${Object.keys(CUSTOMERS).length}`);
  console.log(`  Workers:           ${Object.keys(WORKERS).length} (4 PK + 3 KSA)`);
  console.log(`  Inventory Batches: ${Object.keys(INV_BATCHES).length}`);
  console.log(`  Inventory Items:   ${Object.keys(ALL_INV_ITEMS).length}`);
  console.log(`  Orders:            ${Object.keys(ORDERS).length}`);
  console.log(`  Order Items:       ${Object.keys(ORDER_ITEMS).length}`);
  console.log(`  Expenses:          ${Object.keys(EXPENSES).length}`);
  console.log(`  Worker Payments:   ${Object.keys(WORKER_PAYMENTS).length}`);
  console.log(`  Purchase Orders:   ${Object.keys(PURCHASE_ORDERS).length}`);
  console.log(`  Cash Transactions: ${Object.keys(CASH_TRANSACTIONS).length}`);
}

main().catch(e => { console.error('\nFatal error:', e.message); process.exit(1); });

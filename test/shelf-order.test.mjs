// Regression suite for shelf-order.js's pure helpers (tier rule + payload
// builder). See docs/shelf-copy-suggested-order.md for the feature plan.
//
// Run:  node --test test/shelf-order.test.mjs   (from the repo root)

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const {
  suggestedQtyForDemand, buildShelfOrderPlan, normalizeShelfQty,
  comparePrintCatalogOrder, shelfActionForQty, buildShelfOrderPayload, MAX_SHELF_QTY,
} = require('../shelf-order.js');

// ── Tier rule ─────────────────────────────────────────────────────────────

test('suggestedQtyForDemand: zero or missing demand suggests nothing', () => {
  assert.equal(suggestedQtyForDemand(0), 0);
  assert.equal(suggestedQtyForDemand(undefined), 0);
  assert.equal(suggestedQtyForDemand(null), 0);
});

test('suggestedQtyForDemand: tier boundaries (1-2->1, 3-4->2, 5+->3)', () => {
  assert.equal(suggestedQtyForDemand(1), 1);
  assert.equal(suggestedQtyForDemand(2), 1);
  assert.equal(suggestedQtyForDemand(3), 2);
  assert.equal(suggestedQtyForDemand(4), 2);
  assert.equal(suggestedQtyForDemand(5), 3);
  assert.equal(suggestedQtyForDemand(100), 3);
});

// ── Payload builder / never-lower merge ─────────────────────────────────────

test('buildShelfOrderPlan: no existing store row -> insert', () => {
  const demandRows = [{ catalogId: 'c1', title: 'Title A', openQty: 2 }];
  const { preview, payload } = buildShelfOrderPlan(demandRows, []);
  assert.deepEqual(preview, [
    { catalogId: 'c1', title: 'Title A', distributor: null, itemCode: null, openQty: 2,
      currentQty: 0, hasStoreRow: false, suggestedQty: 1, action: 'insert' },
  ]);
  assert.deepEqual(payload, [{ catalogId: 'c1', quantity: 1 }]);
});

test('buildShelfOrderPlan: existing row below suggestion -> raise', () => {
  const demandRows = [{ catalogId: 'c1', title: 'Title A', openQty: 4 }]; // suggests 2
  const storeRows  = [{ catalogId: 'c1', quantity: 1 }];
  const { preview, payload } = buildShelfOrderPlan(demandRows, storeRows);
  assert.equal(preview[0].action, 'raise');
  assert.equal(preview[0].currentQty, 1);
  assert.equal(preview[0].suggestedQty, 2);
  assert.deepEqual(payload, [{ catalogId: 'c1', quantity: 2 }]);
});

test('buildShelfOrderPlan: existing row equal to suggestion -> no change, not in payload', () => {
  const demandRows = [{ catalogId: 'c1', title: 'Title A', openQty: 2 }]; // suggests 1
  const storeRows  = [{ catalogId: 'c1', quantity: 1 }];
  const { preview, payload } = buildShelfOrderPlan(demandRows, storeRows);
  assert.equal(preview[0].action, 'no change');
  assert.deepEqual(payload, []);
});

test('buildShelfOrderPlan: never-lower — hand-raised store qty above suggestion is untouched', () => {
  const demandRows = [{ catalogId: 'c1', title: 'Title A', openQty: 2 }]; // suggests 1
  const storeRows  = [{ catalogId: 'c1', quantity: 5 }]; // hand-raised
  const { preview, payload } = buildShelfOrderPlan(demandRows, storeRows);
  assert.equal(preview[0].action, 'no change');
  assert.equal(preview[0].currentQty, 5);
  assert.deepEqual(payload, []);
});

test('buildShelfOrderPlan: zero-demand title (absent from demandRows) is never touched, even with a hand-added store row', () => {
  // A title with a hand-added BookStop row but no open customer demand simply
  // never appears in demandRows (the demand query only returns titles with
  // open customer preorders) — buildShelfOrderPlan must not synthesize an
  // action for a store row it was never told about.
  const demandRows = [];
  const storeRows  = [{ catalogId: 'zero-demand-title', quantity: 1 }];
  const { preview, payload } = buildShelfOrderPlan(demandRows, storeRows);
  assert.deepEqual(preview, []);
  assert.deepEqual(payload, []);
});

test('buildShelfOrderPlan: a demand row that resolves to a zero suggestion is omitted entirely', () => {
  // Defensive case — the demand query itself should never emit an openQty of
  // 0, but if it ever did, the row must not appear in preview or payload.
  const demandRows = [{ catalogId: 'c1', title: 'Title A', openQty: 0 }];
  const { preview, payload } = buildShelfOrderPlan(demandRows, []);
  assert.deepEqual(preview, []);
  assert.deepEqual(payload, []);
});

test('buildShelfOrderPlan: mixed batch — insert, raise, and no-change coexist correctly', () => {
  const demandRows = [
    { catalogId: 'insert-me', title: 'A', openQty: 1 },   // suggests 1, no row -> insert
    { catalogId: 'raise-me',  title: 'B', openQty: 5 },    // suggests 3, row at 2 -> raise
    { catalogId: 'no-change', title: 'C', openQty: 3 },    // suggests 2, row at 2 -> no change
  ];
  const storeRows = [
    { catalogId: 'raise-me',  quantity: 2 },
    { catalogId: 'no-change', quantity: 2 },
  ];
  const { preview, payload } = buildShelfOrderPlan(demandRows, storeRows);
  assert.equal(preview.length, 3);
  assert.deepEqual(
    payload.sort((a, b) => a.catalogId.localeCompare(b.catalogId)),
    [
      { catalogId: 'insert-me', quantity: 1 },
      { catalogId: 'raise-me', quantity: 3 },
    ]
  );
});

// ── Print Catalog order (2026-11-24) ─────────────────────────────────────────

test('buildShelfOrderPlan: preview is in Print Catalog order (Lunar band, then PRH, each by title)', () => {
  const demandRows = [
    { catalogId: 'p2', title: 'zebra tales #1', distributor: 'PRH',   itemCode: 'P2', openQty: 1 },
    { catalogId: 'l2', title: 'BATMAN #2',      distributor: 'Lunar', itemCode: 'L2', openQty: 1 },
    { catalogId: 'p1', title: 'Absolute Flash', distributor: 'PRH',   itemCode: 'P1', openQty: 1 },
    { catalogId: 'l1', title: 'batman #10',     distributor: 'Lunar', itemCode: 'L1', openQty: 1 },
  ];
  const { preview, payload } = buildShelfOrderPlan(demandRows, []);
  // Case-insensitive, and "#10" before "#2" (text order, as the database sorts the printed sheet).
  assert.deepEqual(preview.map(r => r.catalogId), ['l1', 'l2', 'p1', 'p2']);
  assert.deepEqual(payload.map(r => r.catalogId), ['l1', 'l2', 'p1', 'p2'], 'payload follows the preview order');
});

test('comparePrintCatalogOrder: equal titles break on item code; unknown distributor sorts last', () => {
  const rows = [
    { distributor: 'Other', title: 'A', itemCode: '1' },
    { distributor: 'Lunar', title: 'Same Title', itemCode: 'B' },
    { distributor: 'Lunar', title: 'same title', itemCode: 'A' },
  ];
  rows.sort(comparePrintCatalogOrder);
  assert.deepEqual(rows.map(r => r.itemCode), ['A', 'B', '1']);
});

// ── Editable Suggested Qty (2026-11-24) ──────────────────────────────────────

test('normalizeShelfQty: whole numbers 0..MAX, blank or junk reads as 0', () => {
  assert.equal(MAX_SHELF_QTY, 99);
  assert.equal(normalizeShelfQty('4'), 4);
  assert.equal(normalizeShelfQty(2.7), 2);
  assert.equal(normalizeShelfQty(''), 0);
  assert.equal(normalizeShelfQty('abc'), 0);
  assert.equal(normalizeShelfQty(-3), 0);
  assert.equal(normalizeShelfQty(500), 99);
});

test('shelfActionForQty: no store row -> insert, or skip at 0', () => {
  const row = { hasStoreRow: false, currentQty: 0 };
  assert.equal(shelfActionForQty(row, 2), 'insert');
  assert.equal(shelfActionForQty(row, 0), 'skip');
});

test('shelfActionForQty: never lowers an existing store quantity', () => {
  const row = { hasStoreRow: true, currentQty: 3 };
  assert.equal(shelfActionForQty(row, 5), 'raise');
  assert.equal(shelfActionForQty(row, 3), 'no change');
  assert.equal(shelfActionForQty(row, 1), 'no change', 'a typed value below the current quantity does not lower it');
  assert.equal(shelfActionForQty(row, 0), 'no change');
});

test('buildShelfOrderPayload: edits override the suggestion; unedited rows keep it', () => {
  const demandRows = [
    { catalogId: 'new-a',   title: 'A', distributor: 'Lunar', itemCode: 'A', openQty: 1 }, // suggests 1, no row
    { catalogId: 'new-b',   title: 'B', distributor: 'Lunar', itemCode: 'B', openQty: 5 }, // suggests 3, no row
    { catalogId: 'have-c',  title: 'C', distributor: 'Lunar', itemCode: 'C', openQty: 5 }, // suggests 3, row at 2
    { catalogId: 'have-d',  title: 'D', distributor: 'Lunar', itemCode: 'D', openQty: 1 }, // suggests 1, row at 1
  ];
  const storeRows = [{ catalogId: 'have-c', quantity: 2 }, { catalogId: 'have-d', quantity: 1 }];
  const { preview } = buildShelfOrderPlan(demandRows, storeRows);
  const edits = new Map([
    ['new-a', '4'],    // raised above the suggestion -> insert 4
    ['new-b', 0],      // skipped
    ['have-c', 1],     // below the current 2 -> no change (never lower)
    ['have-d', 6],     // raised from 1 -> raise to 6
  ]);
  assert.deepEqual(buildShelfOrderPayload(preview, edits), [
    { catalogId: 'new-a', quantity: 4 },
    { catalogId: 'have-d', quantity: 6 },
  ]);
  // A plain object works too, and a row with no edit keeps its suggestion.
  assert.deepEqual(buildShelfOrderPayload(preview, { 'new-a': 2 }), [
    { catalogId: 'new-a', quantity: 2 },
    { catalogId: 'new-b', quantity: 3 },
    { catalogId: 'have-c', quantity: 3 },
  ]);
});

test('buildShelfOrderPayload with no edits equals the plan payload', () => {
  const demandRows = [
    { catalogId: 'x', title: 'X', openQty: 3 },
    { catalogId: 'y', title: 'Y', openQty: 1 },
  ];
  const plan = buildShelfOrderPlan(demandRows, [{ catalogId: 'y', quantity: 4 }]);
  assert.deepEqual(buildShelfOrderPayload(plan.preview, null), plan.payload);
  assert.deepEqual(plan.payload, [{ catalogId: 'x', quantity: 2 }]);
});

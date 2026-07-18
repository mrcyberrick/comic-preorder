// Regression suite for shelf-order.js's pure helpers (tier rule + payload
// builder). See docs/shelf-copy-suggested-order.md for the feature plan.
//
// Run:  node --test test/shelf-order.test.mjs   (from the repo root)

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { suggestedQtyForDemand, buildShelfOrderPlan } = require('../shelf-order.js');

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
    { catalogId: 'c1', title: 'Title A', openQty: 2, currentQty: 0, suggestedQty: 1, action: 'insert' },
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

// Shelf-Copy Suggested Order — pure helpers.
// See docs/shelf-copy-suggested-order.md for the feature plan.
//
// Dual-mode: loaded as a classic <script> on mylist.html (assigns
// window.ShelfOrder) and required from the Node test suite (module.exports).
// No dependencies, no DOM/Supabase access — every input here is data the
// caller already fetched, so these functions stay unit-testable in isolation.

(function (global) {
  'use strict';

  // Tier thresholds (v1 defaults, confirmed with Rick 2026-07-17): total open
  // customer qty for a title -> suggested BookStop shelf qty. Zero open demand
  // suggests nothing — baseline stock comes from the admin's own series
  // subscriptions (auto-reserved by the monthly import), not this feature.
  function suggestedQtyForDemand(openQty) {
    const qty = openQty || 0;
    if (qty < 1) return 0;
    if (qty <= 2) return 1;
    if (qty <= 4) return 2;
    return 3;
  }

  // The highest quantity the editable Suggested Qty accepts — the same cap as
  // My List's quantity stepper (Math.min(99, ...) in mylist.html).
  const MAX_SHELF_QTY = 99;

  // A typed quantity as a whole number from 0 to MAX_SHELF_QTY. Blank, negative
  // or unreadable input reads as 0 (skip), never as an error.
  function normalizeShelfQty(value) {
    const n = Math.floor(Number(value));
    if (!Number.isFinite(n) || n < 0) return 0;
    return Math.min(MAX_SHELF_QTY, n);
  }

  // Print Catalog order (2026-11-24, Rick: "sort by title as in the Print
  // Catalog"). The printed sheet is distributor bands, Lunar then PRH, each
  // sorted by the DATABASE: `order by title, item_code`. Measured on staging's
  // 2026-10 catalog (2,234 rows), a case-insensitive localeCompare('en',
  // { sensitivity: 'base' }) with the item_code tiebreak reproduces the
  // database's order exactly (0 rows out of place, both distributors); a plain
  // byte comparison did not (44 Lunar and 814 PRH rows out of place), and
  // neither did ignoring punctuation. Do not switch to a "natural" numeric
  // sort here: the printed sheet puts "#10" before "#2", and this list should
  // read in the same order as the paper beside it.
  const DISTRIBUTOR_ORDER = { Lunar: 0, PRH: 1 };
  function comparePrintCatalogOrder(a, b) {
    const da = Object.prototype.hasOwnProperty.call(DISTRIBUTOR_ORDER, a.distributor) ? DISTRIBUTOR_ORDER[a.distributor] : 2;
    const db = Object.prototype.hasOwnProperty.call(DISTRIBUTOR_ORDER, b.distributor) ? DISTRIBUTOR_ORDER[b.distributor] : 2;
    if (da !== db) return da - db;
    const t = String(a.title || '').localeCompare(String(b.title || ''), 'en', { sensitivity: 'base' });
    if (t !== 0) return t;
    const ia = String(a.itemCode || ''), ib = String(b.itemCode || '');
    return ia < ib ? -1 : ia > ib ? 1 : 0;
  }

  // What writing `qty` would do to one preview row (the editable Suggested
  // Qty, 2026-11-24). The SAME never-lower rule as buildShelfOrderPlan: an
  // existing store reservation is only ever RAISED here. Lowering one is My
  // List's quantity stepper, where the order-lock rules apply; this tool
  // should never be the thing that quietly cuts a quantity already on order.
  //   no store row:  qty > 0 -> 'insert', qty 0 -> 'skip'
  //   store row:     qty > currentQty -> 'raise', otherwise 'no change'
  function shelfActionForQty(row, qty) {
    const q = normalizeShelfQty(qty);
    if (!row.hasStoreRow) return q > 0 ? 'insert' : 'skip';
    return q > (row.currentQty || 0) ? 'raise' : 'no change';
  }

  // The upsert payload for the preview as it stands, in preview order.
  // edits: a Map (or plain object) of catalogId -> typed qty; a row with no
  // edit uses its suggestedQty, so buildShelfOrderPlan's own payload is this
  // function with no edits.
  function buildShelfOrderPayload(preview, edits) {
    const get = function (id) {
      if (!edits) return undefined;
      if (typeof edits.get === 'function') return edits.get(id);
      return Object.prototype.hasOwnProperty.call(edits, id) ? edits[id] : undefined;
    };
    const payload = [];
    (preview || []).forEach(function (row) {
      const typed = get(row.catalogId);
      const qty = normalizeShelfQty(typed === undefined ? row.suggestedQty : typed);
      const action = shelfActionForQty(row, qty);
      if (action === 'insert' || action === 'raise') {
        payload.push({ catalogId: row.catalogId, quantity: qty });
      }
    });
    return payload;
  }

  // Builds the preview list and the upsert payload from open customer demand
  // vs. BookStop's current store reservations, enforcing the never-lower merge
  // rule: a row is written only when it doesn't yet exist or the suggestion
  // exceeds the current quantity. Hand-raised quantities and zero-demand store
  // rows (not present in demandRows at all) are therefore never touched.
  //
  // demandRows: [{ catalogId, title, openQty, distributor?, itemCode? }] — one
  //   row per title with open (fulfilled = false), non-FOC-locked, non-admin
  //   demand. distributor and itemCode only decide the order (Print Catalog order,
  //   see comparePrintCatalogOrder).
  // storeRows:  [{ catalogId, quantity }] — BookStop admin's current preorders
  //   for the catalog month, any quantity.
  // Returns { preview, payload }.
  //   preview: [{ catalogId, title, distributor, itemCode, openQty, currentQty,
  //     hasStoreRow, suggestedQty, action }], in Print Catalog order. action is
  //     'insert' | 'raise' | 'no change' at the suggested quantity. Only titles
  //     with a nonzero suggestion appear — the "affected titles" list for the modal.
  //   payload: [{ catalogId, quantity }] — insert/raise rows only, ready for
  //     the caller to decorate with user_id/tenant_id and upsert.
  function buildShelfOrderPlan(demandRows, storeRows) {
    const currentByCatalog = new Map(
      (storeRows || []).map(function (r) { return [r.catalogId, r.quantity || 0]; })
    );
    const preview = [];

    (demandRows || []).forEach(function (row) {
      const suggestedQty = suggestedQtyForDemand(row.openQty);
      if (suggestedQty === 0) return;

      const hasRow = currentByCatalog.has(row.catalogId);
      const currentQty = currentByCatalog.get(row.catalogId) || 0;
      const action = !hasRow ? 'insert' : (suggestedQty > currentQty ? 'raise' : 'no change');

      preview.push({
        catalogId: row.catalogId,
        title: row.title,
        distributor: row.distributor || null,
        itemCode: row.itemCode || null,
        openQty: row.openQty,
        currentQty: currentQty,
        hasStoreRow: hasRow,
        suggestedQty: suggestedQty,
        action: action,
      });
    });

    preview.sort(comparePrintCatalogOrder);
    return { preview: preview, payload: buildShelfOrderPayload(preview, null) };
  }

  const ShelfOrder = {
    MAX_SHELF_QTY: MAX_SHELF_QTY,
    suggestedQtyForDemand: suggestedQtyForDemand,
    normalizeShelfQty: normalizeShelfQty,
    comparePrintCatalogOrder: comparePrintCatalogOrder,
    shelfActionForQty: shelfActionForQty,
    buildShelfOrderPayload: buildShelfOrderPayload,
    buildShelfOrderPlan: buildShelfOrderPlan,
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ShelfOrder;
  } else {
    global.ShelfOrder = ShelfOrder;
  }
})(typeof window !== 'undefined' ? window : globalThis);

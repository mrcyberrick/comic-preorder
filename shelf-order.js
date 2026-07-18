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

  // Builds the preview list and the upsert payload from open customer demand
  // vs. BookStop's current store reservations, enforcing the never-lower merge
  // rule: a row is written only when it doesn't yet exist or the suggestion
  // exceeds the current quantity. Hand-raised quantities and zero-demand store
  // rows (not present in demandRows at all) are therefore never touched.
  //
  // demandRows: [{ catalogId, title, openQty }] — one row per title with open
  //   (fulfilled = false), standard-cover, non-FOC-locked, non-admin demand.
  // storeRows:  [{ catalogId, quantity }] — BookStop admin's current preorders
  //   for the catalog month, any quantity.
  // Returns { preview, payload }.
  //   preview: [{ catalogId, title, openQty, currentQty, suggestedQty, action }]
  //     action is 'insert' | 'raise' | 'no change'. Only titles with a nonzero
  //     suggestion appear — this is the "affected titles" list for the modal.
  //   payload: [{ catalogId, quantity }] — insert/raise rows only, ready for
  //     the caller to decorate with user_id/tenant_id and upsert.
  function buildShelfOrderPlan(demandRows, storeRows) {
    const currentByCatalog = new Map(
      (storeRows || []).map(function (r) { return [r.catalogId, r.quantity || 0]; })
    );
    const preview = [];
    const payload = [];

    (demandRows || []).forEach(function (row) {
      const suggestedQty = suggestedQtyForDemand(row.openQty);
      if (suggestedQty === 0) return;

      const hasRow = currentByCatalog.has(row.catalogId);
      const currentQty = currentByCatalog.get(row.catalogId) || 0;
      const action = !hasRow ? 'insert' : (suggestedQty > currentQty ? 'raise' : 'no change');

      preview.push({
        catalogId: row.catalogId,
        title: row.title,
        openQty: row.openQty,
        currentQty: currentQty,
        suggestedQty: suggestedQty,
        action: action,
      });

      if (action === 'insert' || action === 'raise') {
        payload.push({ catalogId: row.catalogId, quantity: suggestedQty });
      }
    });

    return { preview: preview, payload: payload };
  }

  const ShelfOrder = { suggestedQtyForDemand: suggestedQtyForDemand, buildShelfOrderPlan: buildShelfOrderPlan };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ShelfOrder;
  } else {
    global.ShelfOrder = ShelfOrder;
  }
})(typeof window !== 'undefined' ? window : globalThis);

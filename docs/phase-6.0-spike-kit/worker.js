// pulllist-wildcard-spike — Phase 6 gate G1, Q2/Q3 live check (2026-10-22).
// A spike-<label>.pulllist.app name gets a fixed marker response and never reaches the app.
// EVERY other hostname is passed through unchanged, so if the route also catches a production
// hostname (Q3, route collision) that traffic still reaches its real origin instead of breaking.
export default {
  async fetch(request) {
    const host = new URL(request.url).hostname;
    if (/^spike-[a-z0-9]+\.pulllist\.app$/.test(host)) {
      return new Response(`spike ok: ${host}\n`, {
        status: 200,
        headers: { 'Content-Type': 'text/plain; charset=utf-8', 'X-Spike': '1', 'Cache-Control': 'no-store' },
      });
    }
    const res = await fetch(request);
    // Mark pass-through responses so a collision is visible without changing the body.
    const out = new Response(res.body, res);
    out.headers.set('X-Spike-Passthrough', '1');
    return out;
  },
};

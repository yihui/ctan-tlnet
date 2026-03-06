/**
 * Cloudflare Worker: rewrite directory requests to index.html.
 *
 * Only deployed for routes ending in '/' — all other requests
 * (tarballs, tlpdb, etc.) bypass this Worker entirely and go
 * straight to R2.
 *
 * Deploy via Cloudflare Git integration (wrangler.toml).
 */

export default {
  async fetch(request) {
    const url = new URL(request.url);
    url.pathname += "index.html";
    return fetch(url.toString(), request);
  },
};

/**
 * Cloudflare Worker: rewrite the root / to /index.html.
 *
 * Only deployed for tlnet.yihui.org/ — all other requests go
 * directly to R2 without invoking this Worker.
 *
 * Deploy via Cloudflare Git integration (wrangler.toml).
 */

export default {
  async fetch(request) {
    const url = new URL(request.url);
    url.pathname = "/index.html";
    return fetch(url.toString(), request);
  },
};

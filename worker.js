/**
 * Cloudflare Worker: serve index.html for directory requests, and resolve
 * symlinks using a pre-built symlinks.json lookup.
 *
 * Setup:
 *   Add a Worker Route: ctan.yourdomain.com/* -> this Worker.
 *   No R2 bucket binding needed.
 *
 * Deploy via GitHub Actions using wrangler (see wrangler.toml).
 */

// Matches versioned tarballs — these never need symlink resolution
const VERSIONED = /\.r\d+\.tar\.xz$/;

// In-memory cache shared across requests within the same Worker instance
let symlinks = null;
let symlinksLastModified = null;

async function loadSymlinks(baseUrl) {
  // Always do a conditional GET using If-Modified-Since.
  // If symlinks.json hasn't changed since we last loaded it, the server
  // returns 304 and we keep using the cached copy — no re-parsing needed.
  // If it has changed (new sync), we get 200 and reload.
  const headers = symlinksLastModified
    ? { 'If-Modified-Since': symlinksLastModified }
    : {};

  try {
    const res = await fetch(`${baseUrl}/symlinks.json`, { headers });
    if (res.status === 304) {
      // Not modified — keep existing cache
      return symlinks;
    }
    if (res.ok) {
      symlinks = await res.json();
      symlinksLastModified = res.headers.get('Last-Modified');
    }
  } catch (_) {
    // Network error — keep using stale cache if available
  }
  return symlinks;
}

export default {
  async fetch(request) {
    const url = new URL(request.url);

    // Rewrite directory requests to index.html
    if (url.pathname.endsWith('/')) {
      url.pathname += 'index.html';
      return fetch(url.toString(), request);
    }

    // Check symlinks.json for any non-versioned path
    if (!VERSIONED.test(url.pathname)) {
      const map = await loadSymlinks(url.origin);
      const rel = url.pathname.slice(1); // strip leading /
      const target = map?.[rel];
      if (target) {
        url.pathname = '/' + rel.replace(/[^/]+$/, '') + target;
        return Response.redirect(url.toString(), 302);
      }
    }

    return fetch(url.toString(), request);
  },
};

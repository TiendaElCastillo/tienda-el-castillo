const CACHE_NAME = "el-castillo-shell-v47";
const APP_SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./castle-icon.svg",
  "./recargar-free-fire-cuba.html",
  "./assets/game-art.svg?v=6",
  "./assets/free-fire-hero.svg",
  "./assets/product-diamonds.svg",
  "./assets/product-pass.svg",
  "./assets/product-card.svg",
  "./assets/product-level.svg",
  "./assets/castle-logo.webp",
  "./assets/games/free-fire.webp",
  "./assets/admin-panel.css?v=12",
  "./assets/admin-panel.js?v=9"
];

const APP_ROOT = self.registration.scope;
const INDEX_URL = new URL("./index.html", APP_ROOT).href;
const ROOT_URL = new URL("./", APP_ROOT).href;

async function cacheSuccessfulResponse(cache, request, response, cacheKey = request) {
  if (response && response.ok && response.type !== "opaque") {
    try {
      await cache.put(cacheKey, response.clone());
    } catch (_) {
      // Cache quota or storage errors should never break the page.
    }
  }
  return response;
}

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  const isLocal = url.origin === self.location.origin;
  const isSupabaseLibrary =
    url.hostname === "cdn.jsdelivr.net" &&
    url.pathname.includes("/npm/@supabase/supabase-js");

  // Only cache the store shell, its static files and the Supabase browser library.
  // Auth, orders, payment proofs and provider calls stay network-only.
  if (!isLocal && !isSupabaseLibrary) return;

  if (request.mode === "navigate" && isLocal) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      const cachedPage =
        await cache.match(INDEX_URL) ||
        await cache.match(ROOT_URL);

      const networkUpdate = fetch(request)
        .then(response => cacheSuccessfulResponse(cache, request, response, INDEX_URL));

      if (cachedPage) {
        event.waitUntil(networkUpdate.catch(() => {}));
        return cachedPage;
      }

      return networkUpdate.catch(async () => {
        const fallback = await cache.match(INDEX_URL) || await cache.match(ROOT_URL);
        return fallback || Response.error();
      });
    })());
    return;
  }

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request);

    const networkUpdate = fetch(request)
      .then(response => cacheSuccessfulResponse(cache, request, response));

    // Fast path: serve already-downloaded static files immediately, then refresh
    // the cache quietly for the next visit.
    if (cached) {
      event.waitUntil(networkUpdate.catch(() => {}));
      return cached;
    }

    return networkUpdate.catch(() => Response.error());
  })());
});

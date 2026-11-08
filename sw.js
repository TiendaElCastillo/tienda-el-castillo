const CACHE_NAME = "el-castillo-shell-v100";
const APP_SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./castle-icon.svg",
  "./recargar-free-fire-cuba.html",
  "./assets/game-art.svg?v=5",
  "./assets/game-art.svg?v=6",
  "./assets/free-fire-hero.svg",
  "./assets/product-diamonds.svg",
  "./assets/product-pass.svg",
  "./assets/product-card.svg",
  "./assets/product-level.svg",
  "./assets/castle-logo.webp",
  "./assets/games/free-fire.webp",
  "./assets/games/free-fire-tienda.webp",
  "./assets/games/mobile-legends-bang-bang.webp",
  "./assets/admin-panel.css?v=26",
  "./assets/admin-panel.js?v=16",
  "./assets/diamond-pile.svg",
  "./assets/diamond-chest.svg",
  "./assets/ff-diamonds-110.svg",
  "./assets/ff-diamonds-341.svg",
  "./assets/ff-diamonds-572.svg",
  "./assets/ff-diamonds-1166.svg",
  "./assets/ff-diamonds-2398.svg",
  "./assets/ff-diamonds-6160.svg",
  "./assets/ff-diamonds-small-medium.webp",
  "./assets/ff-diamonds-chest-booyah.webp",
  "./assets/ff-weekly-blue-purple.webp",
  "./assets/ff-monthly.webp"
];

const APP_ROOT = self.registration.scope;
const INDEX_URL = new URL("./index.html", APP_ROOT).href;
const ROOT_URL = new URL("./", APP_ROOT).href;

async function cacheUrl(cache, url, cacheKey = url) {
  try {
    const response = await fetch(url, { cache: "reload" });
    if (response && response.ok && response.type !== "opaque") {
      await cache.put(cacheKey, response);
      return true;
    }
  } catch (_) {
    // A missing optional asset must not prevent the store from opening.
  }
  return false;
}

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);

    // Prioritize the actual store page. Optional images and admin files are
    // cached independently so one slow or missing asset cannot cancel install.
    const pageSaved = await cacheUrl(cache, INDEX_URL, INDEX_URL);
    if (pageSaved) await cacheUrl(cache, ROOT_URL, ROOT_URL);

    await Promise.all(APP_SHELL
      .filter(path => path !== "./" && path !== "./index.html")
      .map(path => cacheUrl(cache, new URL(path, APP_ROOT).href)));

    await self.skipWaiting();
  })());
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
    (url.hostname === "cdn.jsdelivr.net" &&
      url.pathname.includes("/npm/@supabase/supabase-js")) ||
    (url.hostname === "unpkg.com" &&
      url.pathname.startsWith("/@supabase/supabase-js@"));
  const isProductArtwork =
    url.hostname === "seagm-media.seagmcdn.com" ||
    url.hostname === "cdn.prod.website-files.com" ||
    url.hostname === "assets.nuuvem.com" ||
    url.hostname === "cdn1.codashop.com";

  // Auth, database reads, orders, payment proofs and provider calls are network-only.
  // Product artwork may be cached after its first successful load for later visits/offline use.
  if (!isLocal && !isSupabaseLibrary && !isProductArtwork) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);

    if (request.mode === "navigate" && isLocal) {
      const cachedPage =
        await cache.match(INDEX_URL) ||
        await cache.match(ROOT_URL);
      if (cachedPage) return cachedPage;

      try {
        const response = await fetch(request);
        if (response && response.ok) {
          await cache.put(INDEX_URL, response.clone()).catch(() => {});
        }
        return response;
      } catch (_) {
        return Response.error();
      }
    }

    const cached = await cache.match(request);
    if (cached) return cached;

    try {
      const response = await fetch(request);
      if (response && ((response.ok && response.type !== "opaque") ||
          (isProductArtwork && response.type === "opaque"))) {
        await cache.put(request, response.clone()).catch(() => {});
      }
      return response;
    } catch (_) {
      return Response.error();
    }
  })());
});

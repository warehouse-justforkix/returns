// Service worker for the JFK Returns tracker — makes the app INSTALLABLE
// ("Install app" / "Add to Dock" / "Add to Home Screen") and lets the shell
// open offline.
//
// Strategy: NETWORK-FIRST for our own files. While online you always get the
// freshest build (this is deliberate — it's what prevents the stale-cache
// problem that once made login look broken). The cache is only a fallback for
// when the network is unavailable. Cross-origin requests (Supabase API,
// esm.sh, jsDelivr) are left entirely to the browser — never intercepted.

const CACHE = "jfk-returns-v23";
const SHELL = [
  "./",
  "./index.html",
  "./style.css?v=23",
  "./app.js?v=23",
  "./config.js",
  "./jfk-logo.png?v=12",
  "./jfk-logo-white.png?v=13",
  "./icon-192.png?v=15",
  "./icon-512.png?v=15",
  "./apple-touch-icon.png?v=15",
  "./manifest.webmanifest?v=19",
];

self.addEventListener("install", (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL).catch(() => {})));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return; // Supabase / CDNs: hands off

  e.respondWith(
    fetch(req)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      })
      .catch(() =>
        caches.match(req).then((r) => r || caches.match("./index.html"))
      )
  );
});

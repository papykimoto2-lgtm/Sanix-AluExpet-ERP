/* Sanix AluExpert ERP — Service worker (mode hors ligne).
   Garde en cache l'application (index.html, config.js, bibliothèques CDN) pour qu'elle s'ouvre
   sans connexion. Les DONNÉES (Supabase) ne passent pas par ici : elles sont gérées dans
   index.html (cache de lecture + file d'attente des saisies, synchronisée au retour du réseau). */
const VERSION = 'aluexpert-v25';
// Bibliothèques : cache PERMANENT (non effacé aux mises à jour) — l'application démarre toujours hors ligne,
// même si une mise à jour a été installée juste avant une coupure.
const CACHE_CDN = 'aluexpert-cdn';
const COQUILLE = ['./', './index.html', './config.js', './manifest.webmanifest', './icon.svg', './icons/icon-192.png', './icons/icon-512.png', './icons/icon-maskable-192.png', './icons/icon-maskable-512.png', './icons/apple-touch-icon.png', './icons/favicon-32.png'];
const BIBLIOTHEQUES = [
  'https://cdn.tailwindcss.com',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js',
  'https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js',
  'https://cdn.jsdelivr.net/npm/three@0.128.0/build/three.min.js',
  'https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/controls/OrbitControls.js',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js',
  'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800;900&display=swap'
];
const CDN = /^https:\/\/(cdn\.tailwindcss\.com|cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)\//;
const estCdn = (url) => CDN.test(url) || url === 'https://cdn.tailwindcss.com';

self.addEventListener('install', (e) => {
  e.waitUntil(Promise.all([
    caches.open(VERSION).then((c) => Promise.all(COQUILLE.map((u) => c.add(u).catch(() => {})))),
    // Bibliothèques absentes du cache permanent : téléchargées dès l'installation (mode no-cors, comme les balises <script>)
    caches.open(CACHE_CDN).then((c) => Promise.all(BIBLIOTHEQUES.map((u) => c.match(u).then((deja) => deja || fetch(new Request(u, { mode: 'no-cors' }))
      .then((res) => (res.ok || res.type === 'opaque') ? c.put(u, res) : null).catch(() => {})))))
  ]).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const cdn = await caches.open(CACHE_CDN);
    for (const k of await caches.keys()) {
      if (k === VERSION || k === CACHE_CDN) continue;
      // Reprise des bibliothèques gardées par une ancienne version avant de l'effacer
      const ancien = await caches.open(k);
      for (const req of await ancien.keys()) {
        if (estCdn(req.url) && !(await cdn.match(req))) { const r = await ancien.match(req); if (r) await cdn.put(req, r); }
      }
      await caches.delete(k);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Pages et fichiers de l'application : réseau d'abord (dernière version), cache si hors ligne
  if (url.origin === self.location.origin) {
    e.respondWith(
      fetch(req).then((res) => {
        if (res.ok) { const copie = res.clone(); caches.open(VERSION).then((c) => c.put(req, copie)); }
        return res;
      }).catch(() => caches.match(req, { ignoreSearch: true })
        .then((r) => r || (req.mode === 'navigate' ? caches.match('./index.html') : Response.error())))
    );
    return;
  }
  // Bibliothèques CDN (Tailwind, Supabase JS, Chart.js, Leaflet…) : cache permanent d'abord, mise à jour en arrière-plan
  if (estCdn(req.url)) {
    e.respondWith(caches.open(CACHE_CDN).then((c) => c.match(req).then((enCache) => {
      const reseau = fetch(req).then((res) => { if (res.ok || res.type === 'opaque') c.put(req, res.clone()); return res; });
      if (enCache) { reseau.catch(() => {}); return enCache; }
      return reseau;
    })));
  }
});

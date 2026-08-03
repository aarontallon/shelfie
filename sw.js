// Service worker mínimo: hace la app instalable (PWA) y cachea el shell +
// dependencias estáticas (CDN) para que cargue más rápido en visitas
// repetidas. NO cachea llamadas a Supabase — los datos siempre tienen que
// venir de red, esto es una app con datos en vivo, no un sitio estático.
const CACHE = 'shelfie-v2';
// Rutas relativas al scope del propio sw.js (p.ej. https://x.github.io/shelfie/),
// nunca con "/" inicial — este sitio vive en un subdirectorio de GitHub Pages,
// no en la raíz del dominio, así que una ruta absoluta apuntaría a otro sitio.
const SHELL = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png']
  .map((p) => new URL(p, self.location).href);
const SHELL_HTML_URL = new URL('./index.html', self.location).href;

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.hostname.includes('supabase.co')) return; // nunca cachear datos en vivo

  if (req.mode === 'navigate') {
    // Shell HTML: cache primero (abre al instante) + red de refresco en segundo
    // plano para la próxima vez — antes era red primero, así que CADA apertura
    // de la app esperaba a descargarse el HTML entero (pesa ~1.3MB) antes de
    // pintar nada, aunque la copia en caché ya estuviera al día. El coste es
    // que un cambio recién publicado tarda una apertura más en verse (la
    // siguiente vez ya sale actualizado); a cambio, abrir la app es instantáneo.
    e.respondWith(
      caches.match(SHELL_HTML_URL).then((cached) => {
        const network = fetch(req).then((res) => {
          if (res && res.ok) caches.open(CACHE).then((c) => c.put(SHELL_HTML_URL, res.clone()));
          return res;
        }).catch(() => cached);
        return cached || network;
      })
    );
    return;
  }

  // Estáticos (CDN de iconos/fuentes/librerías, imágenes propias): cache
  // primero, red de refresco en segundo plano.
  e.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req).then((res) => {
        if (res && res.ok) caches.open(CACHE).then((c) => c.put(req, res.clone()));
        return res;
      }).catch(() => cached);
      return cached || network;
    })
  );
});

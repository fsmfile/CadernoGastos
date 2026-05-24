// Caderno de Gastos — Service Worker
// Estratégia:
// - App shell (HTML, ícones, manifest, fontes): cache-first com revalidação em background
// - Chamadas ao Apps Script: SEMPRE rede (nunca cache — dados precisam estar frescos)
// - Outros recursos: stale-while-revalidate

const VERSION = 'v1.5.4';
const CACHE_NAME = `caderno-gastos-${VERSION}`;

// Recursos essenciais para o app abrir offline
const APP_SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icon.svg',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png',
  './favicon-32.png'
];

// Instalação: pré-cacheia o app shell
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

// Ativação: limpa caches antigos
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

// Fetch: roteamento por tipo de recurso
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Apenas GET é cacheável
  if (request.method !== 'GET') return;

  // NUNCA cachear chamadas ao Apps Script — sempre rede direto
  if (url.hostname === 'script.google.com' || url.hostname.endsWith('.googleusercontent.com')) {
    return; // deixa o navegador lidar normalmente
  }

  // Fontes do Google: stale-while-revalidate (cache rápido, atualiza em background)
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith(staleWhileRevalidate(request));
    return;
  }

  // Mesma origem (app shell): cache-first
  if (url.origin === self.location.origin) {
    event.respondWith(cacheFirst(request));
    return;
  }
});

async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) {
    // Atualiza em background se possível
    fetch(request).then((res) => {
      if (res && res.ok) {
        caches.open(CACHE_NAME).then((c) => c.put(request, res.clone()));
      }
    }).catch(() => {});
    return cached;
  }
  try {
    const res = await fetch(request);
    if (res && res.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, res.clone());
    }
    return res;
  } catch (err) {
    // Fallback para o index se for navegação
    if (request.mode === 'navigate') {
      const fallback = await caches.match('./index.html');
      if (fallback) return fallback;
    }
    throw err;
  }
}

async function staleWhileRevalidate(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  const networkPromise = fetch(request).then((res) => {
    if (res && res.ok) cache.put(request, res.clone());
    return res;
  }).catch(() => cached);
  return cached || networkPromise;
}

// Mensagem para forçar atualização imediata
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

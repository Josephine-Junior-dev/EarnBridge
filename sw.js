const CACHE="earnbridge-v2";
const ASSETS=["./","./index.html","./styles.css","./config.js","./app.js","./manifest.json"];

self.addEventListener("install",event=>{
  event.waitUntil((async()=>{
    const cache=await caches.open(CACHE);
    await cache.addAll(ASSETS);
    await self.skipWaiting();
  })());
});

self.addEventListener("activate",event=>{
  event.waitUntil((async()=>{
    const keys=await caches.keys();
    await Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch",event=>{
  const request=event.request;
  if(request.method!=="GET" || new URL(request.url).origin!==self.location.origin) return;

  const url=new URL(request.url);
  const isAppShell=request.mode==="navigate" ||
    url.pathname.endsWith("/index.html") ||
    url.pathname.endsWith("/app.js") ||
    url.pathname.endsWith("/config.js");

  if(isAppShell){
    event.respondWith((async()=>{
      try{
        const fresh=await fetch(request,{cache:"no-store"});
        const cache=await caches.open(CACHE);
        cache.put(request,fresh.clone());
        return fresh;
      }catch(error){
        const cached=await caches.match(request);
        if(cached) return cached;
        throw error;
      }
    })());
    return;
  }

  event.respondWith((async()=>{
    const cached=await caches.match(request);
    if(cached) return cached;
    const fresh=await fetch(request);
    const cache=await caches.open(CACHE);
    cache.put(request,fresh.clone());
    return fresh;
  })());
});

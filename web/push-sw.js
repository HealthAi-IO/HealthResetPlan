self.addEventListener('push', (event) => {
  const payload = event.data?.json() || {};
  event.waitUntil((async () => {
    const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (clients.some((client) => client.visibilityState === 'visible')) return;
    await self.registration.showNotification(payload.title || '健康重启计划提醒', {
      body: payload.body || '你有一项已设定的健康提醒',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: 'health-reminder',
      data: { url: payload.url || '/clock' },
    });
  })());
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || '/clock', self.location.origin).href;
  event.waitUntil((async () => {
    const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const existing = clients.find((client) => client.url.startsWith(self.location.origin));
    if (existing) {
      await existing.focus();
      if ('navigate' in existing) await existing.navigate(target);
      return;
    }
    await self.clients.openWindow(target);
  })());
});

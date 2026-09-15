// Permission prompts must originate from a user gesture in browsers.
window.gmserpNotifications = {
  async cancel(tag) {
    if (!('serviceWorker' in navigator)) return;
    const registration = await navigator.serviceWorker.getRegistration('/firebase-cloud-messaging-push-scope');
    if (!registration) return;
    for (const notification of await registration.getNotifications(tag ? { tag } : {})) {
      notification.close();
    }
  },
  async permission() {
    if (!('Notification' in window) || !('serviceWorker' in navigator)) return false;
    if (Notification.permission === 'default') {
      return (await Notification.requestPermission()) === 'granted';
    }
    return Notification.permission === 'granted';
  },
  async show(title, body, tag) {
    if (!('Notification' in window) || Notification.permission !== 'granted') return;
    const registration = await navigator.serviceWorker.getRegistration('/firebase-cloud-messaging-push-scope');
    if (registration) await registration.showNotification(title, {
      body, tag, icon: 'icons/Icon-192.png', data: { url: '/?notification=1' },
    });
  },
  async badge(count) {
    document.title = count > 0 ? `(${count > 99 ? '99+' : count}) GMSERP` : 'GMSERP';
    if ('setAppBadge' in navigator) {
      try { await (count > 0 ? navigator.setAppBadge(count) : navigator.clearAppBadge()); }
      catch (_) { /* Unsupported OS or permission denied: tab title remains. */ }
    }
  },
};
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/firebase-messaging-sw.js', {
    scope: '/firebase-cloud-messaging-push-scope',
  }).catch(console.warn);
}

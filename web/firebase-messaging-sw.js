/* Public Firebase client configuration, matching lib/firebase_options.dart. */
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.stopImmediatePropagation();
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    const payload = event.notification.data?.FCM_MSG?.data?.payload || 'notifications';
    const target = new URL('/?notification=1&payload=' + encodeURIComponent(payload), self.location.origin).href;
    for (const client of windows) {
      if (new URL(client.url).origin === self.location.origin) {
        await client.navigate(target);
        return client.focus();
      }
    }
    return clients.openWindow(target);
  })());
});
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');
firebase.initializeApp({
  apiKey: 'AIzaSyAeBYouKxv47RR2s4fmgZs3_QRiFga01rg',
  appId: '1:901927576776:web:3a8d0835845d0ecaf931fd',
  messagingSenderId: '901927576776',
  projectId: 'gmserp-ffc76',
});
firebase.messaging().onBackgroundMessage(async () => {
  // FCM displays the notification payload. Mark the installed app as unread.
  if ('setAppBadge' in navigator) {
    try { await navigator.setAppBadge(); } catch (_) {}
  }
});

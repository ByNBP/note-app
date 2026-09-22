/* eslint-disable no-undef */
/**
 * Web push service worker.
 *
 * Tarayici kapaliyken/sekme arka plandayken gelen FCM mesajlarini bu dosya
 * isler. Dart tarafindaki yapilandirmayi okuyamadigi icin ayni degerlerin
 * buraya da yazilmasi gerekir (flutterfire configure ciktisindaki web
 * bolumu -- lib/firebase_options.dart icindeki `web` sabiti).
 */

importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js',
);

// lib/firebase_options.dart icindeki `web` sabitiyle ayni kalmali.
const firebaseConfig = {
  apiKey: 'AIzaSyCf9lIksECtMS_8aMdC9IKehKgox3V2zoI',
  appId: '1:533163142600:web:0f1c79ba74af7a921ee4fd',
  messagingSenderId: '533163142600',
  projectId: 'note-app-a3675',
  authDomain: 'note-app-a3675.firebaseapp.com',
  storageBucket: 'note-app-a3675.firebasestorage.app',
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

// Sunucu `notification` alani gonderdigi icin tarayici bildirimi kendisi
// gosterir; burada yalnizca tiklama hedefini kaydediyoruz.
messaging.onBackgroundMessage((payload) => {
  const sessionId = payload.data && payload.data.sessionId;
  const title = (payload.notification && payload.notification.title) ||
    'Yeni not';
  const body = (payload.notification && payload.notification.body) || '';

  self.registration.showNotification(title, {
    body,
    tag: sessionId || 'note',
    data: { sessionId },
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const sessionId = event.notification.data && event.notification.data.sessionId;
  const target = sessionId ? `/#/session/${sessionId}` : '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) {
          client.navigate(target);
          return client.focus();
        }
      }
      return clients.openWindow(target);
    }),
  );
});

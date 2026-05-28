importScripts('firebase-config.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

const config = self.FIREBASE_WEB_CONFIG || {};

if (config.apiKey && config.appId) {
  firebase.initializeApp(config);
  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const title =
      payload.notification?.title || payload.data?.title || '단지카';
    const body =
      payload.notification?.body || payload.data?.body || '';

    self.registration.showNotification(title, {
      body,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
    });
  });
}

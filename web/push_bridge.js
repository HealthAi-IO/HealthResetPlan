function hrpUrlBase64ToUint8Array(value) {
  const padding = '='.repeat((4 - value.length % 4) % 4);
  const base64 = (value + padding).replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

window.hrpPushSubscribe = async function (publicKey) {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    throw new Error('当前浏览器不支持通知推送');
  }
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') throw new Error('通知权限未开启');
  const registration = await navigator.serviceWorker.register('/push-sw.js', { scope: '/' });
  await navigator.serviceWorker.ready;
  let subscription = await registration.pushManager.getSubscription();
  if (!subscription) {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: hrpUrlBase64ToUint8Array(publicKey),
    });
  }
  const json = subscription.toJSON();
  return JSON.stringify({
    endpoint: subscription.endpoint,
    p256dh: json.keys.p256dh,
    auth: json.keys.auth,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Shanghai',
  });
};

window.hrpPushUnsubscribe = async function () {
  if (!('serviceWorker' in navigator)) return;
  const registration = await navigator.serviceWorker.getRegistration('/');
  const subscription = await registration?.pushManager.getSubscription();
  await subscription?.unsubscribe();
};

window.hrpPushPermission = function () {
  return 'Notification' in window ? Notification.permission : 'unsupported';
};

const { initializeApp } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const { getMessaging } = require('firebase-admin/messaging');
const { onValueWritten } = require('firebase-functions/v2/database');
const { notificationEvent } = require('./notification_events');
initializeApp();

for (const collection of ['leaveRequests', 'timeCardChangeRequests', 'clockRequests',
  'announcements', 'salaryRateChanges', 'timeCardProfileChanges']) {
  exports[`notify_${collection}`] = onValueWritten({
    ref: `/${collection}/{id}`, region: 'us-central1',
    instance: 'gmserp-ffc76-default-rtdb',
  }, async event => {
    const data = event.data.after.val();
    const notice = notificationEvent(collection, event.data.before.val(), data, event.params.id);
    if (!notice) return;
    const db = getDatabase();
    const companyRef = data.companyDocumentId || data.companyId;
    let company = companyRef ? (await db.ref(`companies/${companyRef}`).get()).val() : null;
    if (!company && data.companyId) {
      const matches = (await db.ref('companies').get()).val() || {};
      company = Object.values(matches).find(item => item.id === data.companyId || item.companyId === data.companyId);
    }
    const users = (await db.ref('users').get()).val() || {};
    const recipients = new Set(notice.recipients);
    const member = uid => !!company?.staff?.[uid];
    if (notice.reviewers) {
      for (const [uid, user] of Object.entries(users)) {
        if (user.role === 'superAdmin' ||
            (!notice.superOnly && user.role === 'admin' && member(uid))) recipients.add(uid);
      }
    }
    for (const uid of recipients) {
      if (!users[uid] || (users[uid].role !== 'superAdmin' && !member(uid))) continue;
      const devices = (await db.ref(`pushTokens/${uid}`).get()).val() || {};
      for (const [key, device] of Object.entries(devices)) {
        if (!device.token || device.enabled === false) continue;
        if (users[uid].role !== 'superAdmin' &&
            ![data.companyId, data.companyDocumentId].includes(device.companyId)) continue;
        try {
          await getMessaging().send({
            token: device.token,
            notification: { title: notice.title, body: 'Open GMSERP to view the latest update.' },
            data: { payload: notice.payload, recipientId: uid,
              entryId: notice.payload.startsWith('notif|') ? notice.payload.slice(6) : `pending:${notice.payload}` },
            android: { priority: 'high', notification: {
              channelId: 'gmserp_outcomes', icon: 'ic_stat_gmserp',
              tag: `${collection}-${event.params.id}`, notificationCount: 1,
            } },
            apns: { payload: { aps: { badge: 1, sound: 'default', threadId: 'gmserp_notifications' } } },
            webpush: { notification: {
              icon: '/icons/Icon-192.png',
              tag: notice.payload.startsWith('notif|') ? notice.payload.slice(6) : 'pending',
            } },
          });
        } catch (error) {
          if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(error.code)) {
            await db.ref(`pushTokens/${uid}/${key}`).remove();
          } else { console.error('Push delivery failed', error.code); }
        }
      }
    }
  });
}

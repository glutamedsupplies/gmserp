# Background notification setup

The app now registers FCM tokens under `pushTokens/{userId}/{tokenHash}`.
Realtime Database functions send background notifications for requests,
outcomes, announcements, and salary/profile updates. Existing database listeners
continue to own foreground alerts. Background badges indicate that updates are
available; opening the app restores the locally calculated unread count.

## Activate

1. Enable Firebase Cloud Messaging and the Cloud Functions billing/API requirements
   for `gmserp-ffc76`. Run `npm ci` in `functions` after installing dependencies.
2. Deploy the reviewed rules and functions: `firebase deploy --only database,functions`.
   This repository change does not deploy them automatically.
3. The supplied Firebase Web Push public key is configured as the default in
   `lib/services/push_notification_service.dart`. Build with `flutter build web`.
   For another Firebase environment, override it using
   `--dart-define=FCM_VAPID_KEY=YOUR_PUBLIC_KEY`.
   Host `notifications.js` and `firebase-messaging-sw.js` with the build over HTTPS
   at the domain root. Do not rewrite the worker request to index.html or cache it
   indefinitely. The worker uses `/firebase-cloud-messaging-push-scope`.
4. On web, enable Notifications in Settings using a click/tap. If already enabled,
   toggle off then on to request browser permission. Install the PWA to use an
   app-icon badge where supported; ordinary tabs use an unread title indicator.
5. Android: rebuild/install, allow notification permission and launcher dots.
6. iOS: upload the APNs authentication key in Firebase; enable Push Notifications
   in the signing team/provisioning profile. **The existing Xcode bundle identifier
   (`com.example.newGmserp`) differs from firebase_options.dart's iOS identifier
   (`com.exampleGmserp.ios`)**. Reconcile the registered Firebase app, plist and
   Xcode signing identifiers before testing. Configure the production push
   entitlement/profile for distribution builds. No signing credentials are included.

## Verify on devices

- Sign in, unlock a company, enable notifications, and confirm a token is registered.
- Minimize each client and create a request/announcement from a different account.
- Confirm one OS notification, an icon indicator, and correct routing when tapped.
- Read the update; confirm the unread badge updates. Android dots follow active
   tray notifications and launcher behavior; Apple/Web numeric badges use the count.
- Disable notifications and repeat; sign out and repeat. Neither should receive
   new notifications. Test token rotation and switching between companies/users.
- Check a nonrecipient and a removed employee cannot receive a company's update.

Delivery depends on network, notification permission, OS background restrictions,
and browser/launcher support. Force-stopped apps and unsupported browsers cannot
be promised identical delivery. Local tests do not substitute for APNs/FCM delivery
tests on physical devices and an HTTPS deployed PWA.

Server dependencies were installed and the handlers loaded successfully. The
dependency audit still reports two moderate transitive advisories (`gaxios` /
`uuid`) after a nonbreaking audit fix; review upstream updates before deployment.

References: https://firebase.google.com/docs/cloud-messaging/flutter/receive
and https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/How_to/Display_badge_on_app_icon

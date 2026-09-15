import 'dart:js_interop';

@JS('gmserpNotifications.permission')
external JSPromise<JSBoolean> _permission();
@JS('gmserpNotifications.show')
external JSPromise<JSAny?> _show(JSString title, JSString body, JSString tag);
@JS('gmserpNotifications.badge')
external JSPromise<JSAny?> _badge(JSNumber count);
@JS('gmserpNotifications.cancel')
external JSPromise<JSAny?> _cancel(JSString tag);

Future<bool> requestWebNotificationPermission() async =>
    (await _permission().toDart).toDart;
Future<void> showWebNotification(String title, String body, String tag) async {
  await _show(title.toJS, body.toJS, tag.toJS).toDart;
}

Future<void> setWebBadge(int count) async {
  await _badge(count.toJS).toDart;
}

Future<void> cancelWebNotification(String tag) async {
  await _cancel(tag.toJS).toDart;
}

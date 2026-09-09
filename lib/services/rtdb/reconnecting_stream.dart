import 'dart:async';

/// Reattaches listeners canceled by the SDK, while leaving ordinary offline
/// reconnection to Firebase. Cancellation also cancels any pending retry.
Stream<T> reconnectingStream<T>(
  Stream<T> Function() connect, {
  Duration retryDelay = const Duration(seconds: 5),
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? retry;
  var stopped = false;
  late void Function() attach;
  void scheduleRetry() {
    if (stopped || retry != null) return;
    retry = Timer(retryDelay, () async {
      retry = null;
      await subscription?.cancel();
      if (!stopped) attach();
    });
  }

  attach = () {
    if (stopped) return;
    try {
      subscription = connect().listen(
        controller.add,
        onError: (Object error, StackTrace stack) {
          if (stopped) return;
          controller.addError(error, stack);
          scheduleRetry();
        },
        onDone: scheduleRetry,
      );
    } catch (error, stack) {
      controller.addError(error, stack);
      scheduleRetry();
    }
  };
  controller = StreamController<T>(
    onListen: attach,
    onCancel: () async {
      stopped = true;
      retry?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}

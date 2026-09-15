import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/services/announcement_live_updates.dart';

void main() {
  test(
    'events refresh immediately and events during a refresh are retained',
    () async {
      final events = StreamController<void>();
      final first = Completer<void>();
      var calls = 0;
      final live = AnnouncementLiveUpdates(
        changes: events.stream,
        refresh: () async {
          calls++;
          if (calls == 1) await first.future;
        },
      );
      live.start();
      expect(calls, 1);
      events.add(null);
      await Future<void>.delayed(Duration.zero);
      first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 3);
      live.dispose();
      events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 3);
      await events.close();
    },
  );

  testWidgets(
    'fallback checks continue without page activation and stop on disposal',
    (tester) async {
      var calls = 0;
      final live = AnnouncementLiveUpdates(
        changes: const Stream<void>.empty(),
        retryInterval: const Duration(seconds: 2),
        refresh: () async {
          calls++;
        },
      );
      live.start();
      await tester.pump();
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 2);
      live.dispose();
      await tester.pump(const Duration(seconds: 4));
      expect(calls, 2);
    },
  );
}

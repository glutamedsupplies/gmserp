import 'dart:async';


import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:new_gmserp/core/utils/realtime_page.dart';
import 'package:new_gmserp/models/user_model.dart';
import 'package:new_gmserp/providers/auth_provider.dart';
import 'package:new_gmserp/services/rtdb/reconnecting_stream.dart';

class _Auth extends ChangeNotifier implements AuthProvider {
  @override
  UserModel? user = const UserModel(
    id: 'u',
    username: 'A',
    email: 'a@b.c',
    phoneNumber: '',
  );
  void signOut() {
    user = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Page extends StatefulWidget {
  const _Page({required this.events, required this.refresh});
  final Stream<void> events;
  final Future<void> Function() refresh;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with RealtimePage {
  @override
  List<String> get realtimePaths => const [];
  @override
  Stream<void> get realtimeChanges => widget.events;
  @override
  Future<void> refreshRealtimeData() => widget.refresh();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {

  testWidgets('coalesces bursts and queues changes arriving during a refresh', (
    tester,
  ) async {
    final auth = _Auth();
    final events = StreamController<void>.broadcast();
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: TickerMode(
          enabled: true,
          child: _Page(
            events: events.stream,
            refresh: () async {
              expect(isRealtimeRefresh, isTrue);
              calls++;
              if (calls == 1) await pending.future;
            },
          ),
        ),
      ),
    );
    events.add(null);
    events.add(null);
    events.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    events.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 2);
    auth.signOut();
    await tester.pump();
    events.add(null);
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    await events.close();
    auth.dispose();
  });

  testWidgets('hidden pages unsubscribe and subscribe again when shown', (
    tester,
  ) async {
    final auth = _Auth();
    var subscriptions = 0;
    var cancellations = 0;
    var calls = 0;
    final events = StreamController<void>.broadcast(
      onListen: () => subscriptions++,
      onCancel: () => cancellations++,
    );
    Widget app(bool visible) => ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: TickerMode(
        enabled: visible,
        child: _Page(
          events: events.stream,
          refresh: () async {
            calls++;
          },
        ),
      ),
    );
    await tester.pumpWidget(app(true));
    expect(subscriptions, 1);
    await tester.pumpWidget(app(false));
    expect(cancellations, 1);
    events.add(null);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    await tester.pumpWidget(app(true));
    expect(subscriptions, 2);
    events.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    await events.close();
    auth.dispose();
  });

  test('failed listeners reconnect and cancellation stops retries', () async {
    var connections = 0;
    final values = <int>[];
    final errors = <Object>[];
    final sources = <StreamController<int>>[];
    final sub = reconnectingStream<int>(
      () {
        connections++;
        final source = StreamController<int>();
        sources.add(source);
        return source.stream;
      },
      retryDelay: const Duration(milliseconds: 10),
    ).listen(values.add, onError: errors.add);
    sources.first.add(1);
    sources.first.addError(StateError('permission temporarily lost'));
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await Future<void>.delayed(Duration.zero);
    expect(connections, 2);
    sources.last.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(values, [1, 2]);
    sources.last.addError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await Future<void>.delayed(Duration.zero);
    expect(connections, 2);
    for (final source in sources) {
      await source.close();
    }
  });
}

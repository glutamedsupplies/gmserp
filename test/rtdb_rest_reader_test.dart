import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:new_gmserp/services/rtdb/rtdb_rest_reader.dart';
import 'package:new_gmserp/services/rtdb/rtdb_service.dart';

void main() {
  test('authenticates reads and refreshes a rejected token once', () async {
    final refreshes = <bool>[];
    final requests = <Uri>[];
    final reader = RtdbRestReader(
      databaseUrl: 'https://example.firebaseio.com/',
      tokenProvider: (refresh) async {
        refreshes.add(refresh);
        return refresh ? 'fresh-token' : 'old-token';
      },
      clientFactory: () => MockClient((request) async {
        requests.add(request.url);
        return requests.length == 1
            ? http.Response('{"error":"Auth token is expired"}', 401)
            : http.Response('{"name":"Company"}', 200);
      }),
    );
    expect(await reader.get('/companies/acme/'), {'name': 'Company'});
    expect(refreshes, [false, true]);
    expect(requests.last.path, '/companies/acme.json');
    expect(requests.last.queryParameters['auth'], 'fresh-token');
  });

  test('keeps permission denial as an error instead of empty data', () async {
    var calls = 0;
    final reader = RtdbRestReader(
      databaseUrl: 'https://example.firebaseio.com',
      tokenProvider: (_) async => 'token',
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{"error":"Permission denied"}', 401);
      }),
    );
    await expectLater(
      reader.get('companies'),
      throwsA(
        isA<FirebaseException>().having(
          (error) => error.code,
          'code',
          'permission-denied',
        ),
      ),
    );
    expect(calls, 2);
  });

  test('does not expose authenticated URLs in connection errors', () async {
    final reader = RtdbRestReader(
      databaseUrl: 'https://example.firebaseio.com',
      tokenProvider: (_) async => 'private-token',
      clientFactory: () => MockClient((request) async {
        throw http.ClientException('Connection failed', request.url);
      }),
    );
    await expectLater(
      reader.get('companies'),
      throwsA(
        isA<FirebaseException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains('private-token')),
        ),
      ),
    );
  });

  test('times out a stalled request', () async {
    final reader = RtdbRestReader(
      databaseUrl: 'https://example.firebaseio.com',
      tokenProvider: (_) async => null,
      timeout: const Duration(milliseconds: 10),
      clientFactory: () => MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      reader.get('companies'),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'Windows polling reads maps, lists and null without native Firebase',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        RtdbService.clearReadCache();
      });
      final responses = <Object?>[
        {
          'name': 'Company',
          'staff': {
            'u1': {'active': true},
          },
        },
        [
          null,
          {'name': 'Company'},
        ],
        null,
      ];
      final service = RtdbService(
        restReader: RtdbRestReader(
          databaseUrl: 'https://example.firebaseio.com',
          tokenProvider: (_) async => 'token',
          clientFactory: () => MockClient(
            (_) async => http.Response(jsonEncode(responses.removeAt(0)), 200),
          ),
        ),
      );
      expect((await service.getMap('companies/acme'))?['name'], 'Company');
      expect(await service.getChildren('companies'), {
        '1': {'name': 'Company'},
      });
      expect(await service.getMap('companies/missing'), isNull);
      expect(responses, isEmpty);
    },
  );
}

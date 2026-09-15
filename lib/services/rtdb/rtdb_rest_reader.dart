import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../firebase_options.dart';

/// Windows native GetValue creates temporary listeners that can trigger the
/// Firebase C++ "Listen() called twice for same QuerySpec" assertion during
/// polling. REST reads use the same signed-in user and database security rules.
class RtdbRestReader {
  RtdbRestReader({
    this.databaseUrl,
    Future<String?> Function(bool forceRefresh)? tokenProvider,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 30),
  }) : _tokenProvider = tokenProvider ?? _currentToken,
       _clientFactory = clientFactory ?? http.Client.new;

  final String? databaseUrl;
  final Future<String?> Function(bool) _tokenProvider;
  final http.Client Function() _clientFactory;
  final Duration timeout;

  static Future<String?> _currentToken(bool forceRefresh) async =>
      FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh);

  Future<Object?> get(String path) async {
    final base = Uri.parse(
      databaseUrl ?? DefaultFirebaseOptions.currentPlatform.databaseURL!,
    );
    final cleanPath = path
        .split('/')
        .where((part) => part.isNotEmpty)
        .join('/');
    final client = _clientFactory();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await _tokenProvider(attempt > 0).timeout(timeout);
        final uri = base.replace(
          path: '/$cleanPath.json',
          queryParameters: {
            ...base.queryParameters,
            if (token != null && token.isNotEmpty) 'auth': token,
          },
        );
        final response = await client.get(uri).timeout(timeout);
        if (response.statusCode == 401 && attempt == 0 && token != null) {
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw FirebaseException(
            plugin: 'firebase_database',
            code: response.statusCode == 401 || response.statusCode == 403
                ? 'permission-denied'
                : 'unavailable',
            message: 'Database read failed (HTTP ${response.statusCode}).',
          );
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
      throw StateError('Database authentication retry exhausted.');
    } on http.ClientException {
      // ClientException can contain the URL, including the user's ID token.
      throw FirebaseException(
        plugin: 'firebase_database',
        code: 'network-error',
        message: 'Unable to connect to the database.',
      );
    } finally {
      // Also cancels an outstanding HTTP request after a timeout.
      client.close();
    }
  }
}

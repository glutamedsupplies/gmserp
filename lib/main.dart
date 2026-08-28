import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/company_provider.dart';
import 'providers/settings_provider.dart';
import 'services/auth_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android auto-inits from google-services.json; Dart may still report empty
  // apps (especially after hot restart). Treat duplicate-app as success.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    final duplicate = (e is FirebaseException && e.code == 'duplicate-app') ||
        e.toString().contains('duplicate-app');
    if (!duplicate) rethrow;
  }

  // Firebase Auth + Realtime Database profiles. Swap implementations if needed.
  final AuthService authService = FirebaseAuthService();
  final settings = SettingsProvider();
  await settings.load();
  await NotificationService.instance.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authService: authService),
        ),
        ChangeNotifierProvider(
          create: (_) => CompanyProvider(),
        ),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: const App(),
    ),
  );
}

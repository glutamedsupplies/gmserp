import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/models/announcement.dart';
import 'package:new_gmserp/widgets/company_announcement_overlay.dart';

void main() {
  testWidgets(
    'popup above Navigator supports semantics, layout and dismissal',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      String? dismissed;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => CompanyAnnouncementPresentation(
            pending: const [
              Announcement(
                id: 'a',
                companyId: 'c',
                companyDocumentId: 'c',
                companyName: 'Company',
                audience: AnnouncementAudience.everyone,
                recipientIds: ['u'],
                subject: 'Meeting',
                message: 'Please attend tomorrow.',
                actorId: 'admin',
                actorName: 'Admin',
              ),
            ],
            onDismiss: (id) => dismissed = id,
            child: child!,
          ),
          home: const Scaffold(body: Text('Dashboard')),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Meeting'), findsOneWidget);
      expect(find.text('For you, by Company'), findsOneWidget);
      expect(find.text('Announced from: Time unavailable'), findsOneWidget);
      expect(find.text('From: Admin'), findsOneWidget);
      await tester.tap(find.text('Okay'));
      await tester.pumpAndSettle();
      expect(dismissed, 'a');
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

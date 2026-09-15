import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/models/announcement.dart';
import 'package:new_gmserp/widgets/dashboard_announcements.dart';

void main() {
  testWidgets(
    'dashboard card shows full announcement details on a narrow screen',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                AnnouncementDashboardCard(
                  announcement: Announcement(
                    id: 'a',
                    companyId: 'c',
                    companyDocumentId: 'c',
                    companyName: 'Example Company',
                    audience: AnnouncementAudience.specific,
                    recipientIds: const ['u'],
                    subject: 'Updated work schedule',
                    message:
                        'Please arrive at 9 AM.\nBring your attendance record.',
                    actorId: 'admin',
                    actorName: 'Office Admin',
                    createdAt: DateTime(2026, 9, 14, 8, 30),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Updated work schedule'), findsOneWidget);
      expect(
        find.text('Please arrive at 9 AM.\nBring your attendance record.'),
        findsOneWidget,
      );
      expect(find.text('For you'), findsOneWidget);
      expect(find.text('From: Office Admin'), findsOneWidget);
      expect(find.textContaining('2026-09-14 08:30:00 AM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}


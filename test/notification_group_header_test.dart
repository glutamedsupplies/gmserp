import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/widgets/notification_group_header.dart';

void main() {
  test('groups only when there are more than two notifications', () {
    expect(NotificationGroupHeader.shouldGroup(0), isFalse);
    expect(NotificationGroupHeader.shouldGroup(1), isFalse);
    expect(NotificationGroupHeader.shouldGroup(2), isFalse);
    expect(NotificationGroupHeader.shouldGroup(3), isTrue);
  });

  testWidgets('notification group can be expanded and collapsed', (
    tester,
  ) async {
    var expanded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                NotificationGroupHeader(
                  count: 3,
                  expanded: expanded,
                  onChanged: (value) => setState(() => expanded = value),
                ),
                if (expanded) const Text('Notification details'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('3 notifications'), findsOneWidget);
    expect(find.text('Notification details'), findsNothing);
    await tester.tap(find.text('3 notifications'));
    await tester.pump();
    expect(find.text('Notification details'), findsOneWidget);
    await tester.tap(find.text('3 notifications'));
    await tester.pump();
    expect(find.text('Notification details'), findsNothing);
  });
}

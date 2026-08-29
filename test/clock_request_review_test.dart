import 'package:flutter_test/flutter_test.dart';

import 'package:new_gmserp/models/clock_request.dart';

void main() {
  group('ClockRequest.awaitsReview', () {
    ClockRequest requestWithStatus(String status) {
      return ClockRequest(
        id: 'c1',
        type: ClockRequest.typeClockIn,
        status: status,
        userId: 'u1',
        username: 'Pat',
        userEmail: 'pat@example.com',
        companyId: 'co1',
        companyDocumentId: 'doc1',
        companyName: 'Acme',
        workDate: '2026-08-28',
        requestedAt: DateTime(2026, 8, 28, 9),
      );
    }

    test('pending requests await review', () {
      expect(requestWithStatus('pending').awaitsReview, isTrue);
    });

    test('expired requests can still be reviewed', () {
      expect(requestWithStatus('expired').awaitsReview, isTrue);
    });

    test('approved requests do not await review', () {
      expect(requestWithStatus('approved').awaitsReview, isFalse);
    });
  });
}

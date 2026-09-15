const { test } = require('node:test');
const assert = require('node:assert/strict');
const { notificationEvent: event } = require('./notification_events');
test('only status transitions notify request participants', () => {
  assert.equal(event('leaveRequests', { status: 'approved' }, { status: 'approved' }, 'a'), null);
  assert.deepEqual(event('leaveRequests', { status: 'pending' },
    { status: 'approved', userId: 'u' }, 'a').recipients, ['u']);
  assert.equal(event('timeCardChangeRequests', null, { status: 'pending' }, 'a').superOnly, true);
});
test('announcements target explicit recipients and do not repeat on edits', () => {
  assert.deepEqual(event('announcements', null, { recipientIds: { a: true, b: false } }, 'x').recipients, ['a']);
  assert.equal(event('announcements', {}, {}, 'x'), null);
  assert.equal(event('announcements', {}, null, 'x'), null);
});

// Keep notification routing independent of Firebase so it is testable.
function notificationEvent(collection, before, after, id) {
  if (!after) return null;
  const kinds = { leaveRequests: 'leave', timeCardChangeRequests: 'time', clockRequests: 'clock' };
  const type = kinds[collection];
  if (type) {
    if (before?.status === after.status) return null;
    if (after.status === 'pending') {
      return { reviewers: true, superOnly: type === 'time', recipients: [],
        title: 'New request', payload: `${type}|${id}` };
    }
    if (!['approved', 'rejected', 'declined'].includes(after.status)) return null;
    return { recipients: [...new Set([after.userId, after.employeeId, after.requesterId].filter(Boolean))],
      title: 'Request updated', payload: `notif|${type}:${id}` };
  }
  if (before) return null;
  if (collection === 'announcements') {
    const ids = Array.isArray(after.recipientIds) ? after.recipientIds :
      Object.keys(after.recipientIds || {}).filter(key => after.recipientIds[key] === true);
    return { recipients: ids, title: 'New announcement', payload: `notif|announce:${id}` };
  }
  if (['salaryRateChanges', 'timeCardProfileChanges'].includes(collection)) {
    const ids = Array.isArray(after.recipientIds) ? after.recipientIds : Object.keys(after.recipientIds || {}).filter(key => after.recipientIds[key] === true);
    return { recipients: [...new Set([...ids, after.employeeId || after.userId].filter(Boolean))],
      title: 'Employee record updated', payload: 'notifications' };
  }
  return null;
}
module.exports = { notificationEvent };

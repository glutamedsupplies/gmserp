import 'package:flutter/material.dart';

/// One expandable heading once a notification list contains three or more.
class NotificationGroupHeader extends StatelessWidget {
  const NotificationGroupHeader({
    super.key,
    required this.count,
    required this.expanded,
    required this.onChanged,
  });

  final int count;
  final bool expanded;
  final ValueChanged<bool> onChanged;

  static bool shouldGroup(int count) => count > 2;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.notifications_rounded),
      title: Text('$count notifications'),
      subtitle: Text(
        expanded ? 'Tap to collapse' : 'Tap to view notifications',
      ),
      trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
      onTap: () => onChanged(!expanded),
    ),
  );
}

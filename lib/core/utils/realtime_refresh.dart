import 'dart:async';

final _refreshZoneKey = Object();

bool get isRealtimeRefresh => Zone.current[_refreshZoneKey] == true;

Future<void> runRealtimeRefresh(Future<void> Function() action) =>
    runZoned(action, zoneValues: {_refreshZoneKey: true});

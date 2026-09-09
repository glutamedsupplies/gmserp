import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/core/utils/active_page_load.dart';

class _Page extends StatefulWidget {
  const _Page({required this.onLoad});
  final VoidCallback onLoad;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with ActivePageLoad {
  @override
  void onPageActivated() => widget.onLoad();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('cached pages reload when shown, but not on ordinary rebuilds', (
    tester,
  ) async {
    var loads = 0;
    Widget page(bool enabled) => TickerMode(
      enabled: enabled,
      child: _Page(onLoad: () => loads++),
    );

    await tester.pumpWidget(page(false));
    expect(loads, 0);
    await tester.pumpWidget(page(true));
    expect(loads, 1);
    await tester.pumpWidget(page(true));
    expect(loads, 1);
    await tester.pumpWidget(page(false));
    await tester.pumpWidget(page(true));
    expect(loads, 2);
  });

  testWidgets('resume refreshes only the visible page and disposal is safe', (
    tester,
  ) async {
    var loads = 0;
    Widget page(bool enabled) => TickerMode(
      enabled: enabled,
      child: _Page(onLoad: () => loads++),
    );
    await tester.pumpWidget(page(true));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(loads, 2);
    await tester.pumpWidget(page(false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(loads, 2);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}


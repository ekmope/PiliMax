import 'package:PiliMax/common/widgets/floating_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Widget> destinations() => const [
    FloatingNavigationDestination(
      icon: Icon(Icons.home_outlined),
      label: 'Home',
    ),
    FloatingNavigationDestination(
      icon: Icon(Icons.bolt_outlined),
      label: 'Dynamic',
    ),
    FloatingNavigationDestination(
      icon: Icon(Icons.person_outline),
      label: 'Mine',
    ),
  ];

  Widget host({
    ValueChanged<int>? onSelected,
    int selectedIndex = 0,
  }) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: _NavigationHost(
        initialIndex: selectedIndex,
        onSelected: onSelected,
        destinations: destinations(),
      ),
    );
  }

  testWidgets('liquid glass mode adds a clipped backdrop filter', (
    tester,
  ) async {
    await tester.pumpWidget(host(onSelected: (_) {}));

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('tap and horizontal drag select destinations', (tester) async {
    var selected = 0;
    await tester.pumpWidget(host(onSelected: (value) => selected = value));

    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    expect(selected, 2);

    await tester.drag(
      find.byType(FloatingNavigationBar),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    expect(selected, 1);
  });
}

class _NavigationHost extends StatefulWidget {
  const _NavigationHost({
    required this.destinations,
    this.initialIndex = 0,
    this.onSelected,
  });

  final List<Widget> destinations;
  final int initialIndex;
  final ValueChanged<int>? onSelected;

  @override
  State<_NavigationHost> createState() => _NavigationHostState();
}

class _NavigationHostState extends State<_NavigationHost> {
  late int selectedIndex = widget.initialIndex;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: const SizedBox.expand(),
    bottomNavigationBar: FloatingNavigationBar(
      liquidGlass: true,
      selectedIndex: selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: widget.destinations,
      onDestinationSelected: (index) {
        setState(() => selectedIndex = index);
        widget.onSelected?.call(index);
      },
    ),
  );
}

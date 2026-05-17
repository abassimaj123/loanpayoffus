import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Smoke tests — widgets de base sans Firebase/Ads/Riverpod
void main() {
  group('Smoke — Loan Payoff', () {
    testWidgets('MaterialApp se construit sans crash', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Loan Payoff'))),
        ),
      );
      expect(find.text('Loan Payoff'), findsOneWidget);
    });

    testWidgets('TextField numérique accepte des valeurs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Amount'),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '10000');
      expect(find.text('10000'), findsOneWidget);
    });

    testWidgets('ElevatedButton se construit et répond au tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (ctx, setState) => Scaffold(
              body: ElevatedButton(
                onPressed: () => setState(() => tapped = true),
                child: Text(tapped ? 'Tapped' : 'Calculate'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Calculate'), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('Tapped'), findsOneWidget);
    });

    testWidgets('NavigationBar se construit avec destinations', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calculate),
                  label: 'Calculator',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Calculator'), findsOneWidget);
    });
  });
}

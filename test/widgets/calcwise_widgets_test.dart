import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal host — no Firebase, no AdMob, no IAP.
Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF512DA8)),
        extensions: [CalcwiseTheme.light(primary: const Color(0xFF512DA8))],
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ResultTile', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_host(
        const ResultTile(label: 'Payoff Date', value: 'Mar 2031'),
      ));
      await tester.pump();
      expect(find.text('Payoff Date'), findsOneWidget);
      expect(find.text('Mar 2031'), findsOneWidget);
    });

    testWidgets('highlighted tile renders without error', (tester) async {
      await tester.pumpWidget(_host(
        const ResultTile(
          label: 'Interest Saved',
          value: r'$4,820',
          isHighlight: true,
        ),
      ));
      await tester.pump();
      expect(find.text('Interest Saved'), findsOneWidget);
      expect(find.text(r'$4,820'), findsOneWidget);
    });

    testWidgets('renders payoff breakdown tiles', (tester) async {
      await tester.pumpWidget(_host(
        const Column(
          children: [
            ResultTile(label: 'Current Balance', value: r'$28,500'),
            ResultTile(label: 'Monthly Payment', value: r'$650'),
            ResultTile(label: 'Extra Payment', value: r'$200'),
            ResultTile(label: 'New Payoff Date', value: 'Oct 2028'),
            ResultTile(label: 'Interest Saved', value: r'$4,820'),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Current Balance'), findsOneWidget);
      expect(find.text('Monthly Payment'), findsOneWidget);
      expect(find.text('Extra Payment'), findsOneWidget);
      expect(find.text('New Payoff Date'), findsOneWidget);
      expect(find.text('Interest Saved'), findsOneWidget);
    });
  });

  group('CalcwiseHeroCard', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Debt Free In',
          value: '3.5 yrs',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('DEBT FREE IN'), findsOneWidget);
      expect(find.text('3.5 yrs'), findsOneWidget);
    });

    testWidgets('renders secondary text', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Payoff Date',
          value: 'Oct 2028',
          secondary: r'with extra $200/mo',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(r'with extra $200/mo'), findsOneWidget);
    });

    testWidgets('renders stats row', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Time Saved',
          value: '2.1 yrs',
          stats: [
            (label: 'Interest Saved', value: r'$4,820'),
            (label: 'Payoff Date', value: 'Oct 2028'),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('INTEREST SAVED'), findsOneWidget);
      expect(find.text('PAYOFF DATE'), findsOneWidget);
    });

    testWidgets('renders badge', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Debt Free In',
          value: '3.5 yrs',
          badges: [CalcwiseHeroBadge(label: 'Avalanche')],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Avalanche'), findsOneWidget);
    });
  });

  group('SectionCard', () {
    testWidgets('renders title and children', (tester) async {
      await tester.pumpWidget(_host(
        const SectionCard(
          title: 'Payoff Summary',
          children: [
            ResultTile(label: 'Original Payoff', value: 'Mar 2031'),
            ResultTile(label: 'New Payoff', value: 'Oct 2028'),
            ResultTile(label: 'Months Saved', value: '29'),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Payoff Summary'), findsOneWidget);
      expect(find.text('Original Payoff'), findsOneWidget);
      expect(find.text('New Payoff'), findsOneWidget);
      expect(find.text('Months Saved'), findsOneWidget);
    });

    testWidgets('renders debt strategy section', (tester) async {
      await tester.pumpWidget(_host(
        const SectionCard(
          title: 'Debt Avalanche',
          children: [
            ResultTile(label: 'Highest APR', value: '24.9%'),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Debt Avalanche'), findsOneWidget);
    });
  });

  group('CalcwiseEmptyState', () {
    testWidgets('renders icon and title', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseEmptyState(
          icon: Icons.trending_down_rounded,
          title: 'No loans added',
          body: 'Add a loan to see your payoff plan.',
        ),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
      expect(find.text('No loans added'), findsOneWidget);
      expect(find.text('Add a loan to see your payoff plan.'), findsOneWidget);
    });

    testWidgets('action button fires callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(_host(
        CalcwiseEmptyState(
          icon: Icons.add_circle_outline_rounded,
          title: 'No goals set',
          actionLabel: 'Add a loan',
          onAction: () => tapped = true,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Add a loan'));
      expect(tapped, isTrue);
    });

    testWidgets('renders without action when not provided', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseEmptyState(
          icon: Icons.trending_down_rounded,
          title: 'No data',
        ),
      ));
      await tester.pump();
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}

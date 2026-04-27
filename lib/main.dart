import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'core/ads/ad_service.dart';
import 'core/freemium/freemium_service.dart';
import 'core/freemium/iap_service.dart';
import 'core/freemium/paywall_service.dart';
import 'core/firebase/firebase_options.dart';
import 'core/firebase/crashlytics_service.dart';
import 'core/firebase/analytics_service.dart';
import 'core/language/language_notifier.dart';
import 'l10n/strings_en.dart';
import 'l10n/strings_es.dart';
import 'presentation/screens/calculator/calculator_screen.dart';
import 'presentation/screens/payoff_plan/payoff_plan_screen.dart';
import 'presentation/screens/comparison/comparison_screen.dart';
import 'presentation/screens/goals/goals_screen.dart';
import 'presentation/screens/history/history_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/widgets/paywall_soft.dart';
import 'presentation/widgets/paywall_hard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CrashlyticsService.init();
  await freemiumService.initialize();
  await paywallService.init();
  await IAPService.instance.initialize();
  await AdService.instance.initialize();
  await AnalyticsService.instance.logAppOpen();
  runApp(const ProviderScope(child: LoanPayoffUSApp()));
}

class LoanPayoffUSApp extends StatelessWidget {
  const LoanPayoffUSApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Loan Payoff US',
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.system,
    home: const _MainShell(),
    debugShowCheckedModeBanner: false,
  );
}

class _MainShell extends StatefulWidget {
  const _MainShell();
  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;

  static const _screens = [
    CalculatorScreen(),
    PayoffPlanScreen(),
    ComparisonScreen(),
    GoalsScreen(),
    HistoryScreen(),
  ];

  static const _icons = [
    Icons.calculate_rounded,
    Icons.receipt_long_rounded,
    Icons.compare_arrows_rounded,
    Icons.flag_rounded,
    Icons.history_rounded,
  ];
  static const _iconsOutlined = [
    Icons.calculate_outlined,
    Icons.receipt_long_outlined,
    Icons.compare_arrows,
    Icons.flag_outlined,
    Icons.history_outlined,
  ];

  static const _tabNames = ['Calculator', 'PayoffPlan', 'Comparison', 'Goals', 'History'];

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
    // Observe IAP errors and surface via Snackbar
    IAPService.instance.iapErrorNotifier.addListener(_onIapError);
    // Record session and show paywall gate if needed
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordSession());
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    IAPService.instance.iapErrorNotifier.removeListener(_onIapError);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  void _onIapError() {
    final msg = IAPService.instance.iapErrorNotifier.value;
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _recordSession() async {
    final gate = await paywallService.recordSession();
    if (!mounted) return;
    await AnalyticsService.instance.logSessionStart(
        sessionNumber: paywallService.sessionCount);
    if (gate == PaywallGate.hard) {
      await PaywallHard.show(context);
    } else if (gate == PaywallGate.soft) {
      await PaywallSoft.show(context);
    }
  }

  Future<void> _onTabSelected(int i) async {
    setState(() => _index = i);
    await AnalyticsService.instance.logTabSwitch(tabName: _tabNames[i]);
    // recordAction on tab switch — may trigger paywall
    final gate = await paywallService.recordAction();
    if (!mounted) return;
    if (gate == PaywallGate.hard) {
      await PaywallHard.show(context);
    } else if (gate == PaywallGate.soft) {
      await PaywallSoft.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();

    final labels = [s.navCalculator, s.navPayoffPlan, s.navComparison, s.navGoals, s.navHistory];

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary, AppTheme.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.monetization_on_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text(s.appTitle,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19)),
            ]),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          )],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onTabSelected,
          destinations: List.generate(labels.length, (i) => NavigationDestination(
            icon: Icon(_iconsOutlined[i]),
            selectedIcon: Icon(_icons[i], color: AppTheme.primary),
            label: labels[i],
          )),
        ),
      ),
    );
  }
}

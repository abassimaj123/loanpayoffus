import 'dart:async';
import 'package:calcwise_core/calcwise_core.dart' hide CrashlyticsService;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'core/theme/app_theme.dart';
import 'core/ads/ad_service.dart';
import 'core/freemium/freemium_service.dart';
import 'core/freemium/iap_service.dart';

final paywallSession = PaywallSessionService(appKey: 'loanpayoffus');
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
import 'presentation/screens/debt_strategy/debt_strategy_screen.dart';
import 'presentation/widgets/paywall_soft.dart';
import 'presentation/widgets/paywall_hard.dart';
import 'presentation/widgets/premium_badge.dart';
import 'presentation/screens/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CrashlyticsService.init();
  await loadSavedLanguage();
  await themeModeService.initialize();
  await freemiumService.initialize();
  await paywallSession.initialize();
  await IAPService.instance.initialize();
  await _requestConsent();
  await AdService.instance.initialize();
  await AnalyticsService.instance.logAppOpen();
  final isFirstSession = paywallSession.sessionCount == 0;
  runApp(ProviderScope(child: LoanPayoffUSApp(showSplash: isFirstSession)));
}

class LoanPayoffUSApp extends StatelessWidget {
  final bool showSplash;
  const LoanPayoffUSApp({super.key, this.showSplash = false});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeService.notifier,
          builder: (context, themeMode, child) => MaterialApp(
            title: 'Loan Payoff US',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            home: showSplash
                ? const SplashScreen(child: _MainShell())
                : const _MainShell(),
            debugShowCheckedModeBanner: false,
          ),
        );
      },
    );
  }
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
    DebtStrategyScreen(),
    HistoryScreen(),
  ];

  static const _icons = [
    Icons.calculate_rounded,
    Icons.receipt_long_rounded,
    Icons.compare_arrows_rounded,
    Icons.flag_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.history_rounded,
  ];
  static const _iconsOutlined = [
    Icons.calculate_outlined,
    Icons.receipt_long_outlined,
    Icons.compare_arrows,
    Icons.flag_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.history_outlined,
  ];

  static const _tabNames = ['Calculator', 'PayoffPlan', 'Comparison', 'Goals', 'Strategy', 'History'];

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
        backgroundColor: AppTheme.dangerRed,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _recordSession() async {
    await paywallSession.recordSession();
    if (!mounted) return;
    await AnalyticsService.instance.logSessionStart(
        sessionNumber: paywallSession.sessionCount);
  }

  Future<void> _onTabSelected(int i) async {
    setState(() => _index = i);
    await AnalyticsService.instance.logTabSwitch(tabName: _tabNames[i]);
    // recordAction on tab switch — may trigger paywall
    final gate = await paywallSession.recordAction();
    if (!mounted) return;
    if (gate == PaywallTrigger.hard) {
      await PaywallHard.show(context);
    } else if (gate == PaywallTrigger.soft) {
      await PaywallSoft.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();

    final labels = [s.navCalculator, s.navPayoffPlan, s.navComparison, s.navGoals, s.navDebtStrategy, s.navHistory];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));

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
              const PremiumBadge(),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const SettingsScreen(),
                    transitionsBuilder: (_, anim, __, child) =>
                        FadeTransition(opacity: anim, child: child),
                    transitionDuration: const Duration(milliseconds: 250),
                  ),
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


/// Request GDPR/PIPEDA consent via Google UMP SDK.
/// Resolves on success, timeout, or error so the app always launches.
/// On non-EEA/UK devices the UMP SDK completes immediately without showing a form.
Future<void> _requestConsent() async {
  final completer = Completer<void>();
  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () async {
      // Consent info updated — show form only if required
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        ConsentForm.loadAndShowConsentFormIfRequired(
          (_) { if (!completer.isCompleted) completer.complete(); },
        );
      } else {
        if (!completer.isCompleted) completer.complete();
      }
    },
    (_) { if (!completer.isCompleted) completer.complete(); },
  );
  return completer.future;
}

import 'package:calcwise_core/calcwise_core.dart' hide CrashlyticsService, PaywallHard;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'core/freemium/freemium_service.dart';
import 'core/freemium/iap_service.dart';
import 'core/firebase/firebase_options.dart';
import 'core/firebase/crashlytics_service.dart';
import 'core/firebase/analytics_service.dart';
import 'core/language/language_notifier.dart';
import 'l10n/strings_en.dart';
import 'l10n/strings_es.dart';
import 'presentation/screens/calculator/calculator_screen.dart';
import 'presentation/screens/payoff_plan/payoff_plan_screen.dart';
// comparison_screen.dart — accessible from within PayoffPlanScreen via push
// import 'presentation/screens/comparison/comparison_screen.dart';
import 'presentation/screens/goals/goals_screen.dart';
import 'presentation/screens/history/history_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/debt_strategy/debt_strategy_screen.dart';
import 'presentation/widgets/paywall_soft.dart';
import 'presentation/widgets/paywall_hard.dart';
import 'presentation/screens/splash/splash_screen.dart';
import 'core/services/loan_notification_service.dart';

final paywallSession = PaywallSessionService(
  appKey: 'loanpayoffus',
  hasFullAccess: () => freemiumService.hasFullAccess,
);

final adService = CalcwiseAdService(
  config: CalcwiseAdConfig(
    bannerAndroid: kReleaseMode
        ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
        : 'ca-app-pub-3940256099942544/6300978111',
    interstitialAndroid: kReleaseMode
        ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
        : 'ca-app-pub-3940256099942544/1033173712',
    rewardedAndroid: kReleaseMode
        ? 'ca-app-pub-5379540026739666/XXXXXXXXXX'
        : 'ca-app-pub-3940256099942544/5224354917',
    calcThreshold: 8,
    cooldownMinutes: 5,
  ),
  freemium: freemiumService,
  analytics: AnalyticsService.instance,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CrashlyticsService.init();
  await loadSavedLanguage();
  await themeModeService.initialize();
  await freemiumService.initialize();
  await LoanNotificationService.initialize();
  await LoanNotificationService.scheduleMonthlyCheckin(isSpanishNotifier.value);
  await paywallSession.initialize();
  await IAPService.instance.initialize();
  await requestCalcwiseConsent();
  await adService.initialize();
  await AnalyticsService.instance.logAppOpen();
  CalcwiseAdFooter.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
    onGetPremium: () => IAPService.instance.buy(),
  );
  CalcwiseRewardAdSheet.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
  );
  runApp(const ProviderScope(child: LoanPayoffUSApp(showSplash: true)));
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
            navigatorObservers: [
              FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
            ],
            home: showSplash
                ? const SplashScreen(child: _MainShell())
                : const _MainShell(),
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              if (!MediaQuery.of(context).disableAnimations) return child!;
              return Theme(
                data: Theme.of(context).copyWith(
                  pageTransitionsTheme: const PageTransitionsTheme(
                    builders: {
                      TargetPlatform.android: _NoAnimPageTransitionsBuilder(),
                      TargetPlatform.iOS: _NoAnimPageTransitionsBuilder(),
                    },
                  ),
                ),
                child: child!,
              );
            },
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
  bool _wasPremium = false;

  static const _screens = [
    CalculatorScreen(),
    PayoffPlanScreen(),
    DebtStrategyScreen(),
    GoalsScreen(),
    HistoryScreen(),
  ];

  static const _icons = [
    Icons.calculate_rounded,
    Icons.receipt_long_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.flag_rounded,
    Icons.history_rounded,
  ];
  static const _iconsOutlined = [
    Icons.calculate_rounded,
    Icons.receipt_long_rounded,
    Icons.account_balance_wallet_outlined,
    Icons.flag_outlined,
    Icons.history_rounded,
  ];

  static const _tabNames = [
    'Calculator',
    'PayoffPlan',
    'Strategy',
    'Goals',
    'History',
  ];

  @override
  void initState() {
    super.initState();
    _wasPremium = freemiumService.hasFullAccess;
    isSpanishNotifier.addListener(_onLangChange);
    freemiumService.isPremiumNotifier.addListener(_onPremiumChange);
    iapErrorNotifier.addListener(_onIapError);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordSession());
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    freemiumService.isPremiumNotifier.removeListener(_onPremiumChange);
    iapErrorNotifier.removeListener(_onIapError);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  void _onPremiumChange() {
    final now = freemiumService.hasFullAccess;
    if (now && !_wasPremium && mounted) {
      showPremiumWelcomeSnackBar(context, isSpanish: isSpanishNotifier.value);
    }
    _wasPremium = now;
  }

  void _onIapError() {
    final msg = iapErrorNotifier.value;
    if (msg == null || !mounted) return;
    showIapErrorSnackBar(context, msg);
    iapErrorNotifier.value = null;
  }

  Future<void> _recordSession() async {
    await paywallSession.recordSession();
    if (!mounted) return;
    await AnalyticsService.instance.logSessionStart(
      sessionNumber: paywallSession.sessionCount,
    );
  }

  Future<void> _onTabSelected(int i) async {
    // All tabs accessible — premium features gated inside each screen
    setState(() => _index = i);
    await AnalyticsService.instance.logTabSwitch(tabName: _tabNames[i]);
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.hard) {
      PaywallHard.show(context);
    } else if (trigger == PaywallTrigger.soft) {
      PaywallSoft.show(context, featureTitle: 'Full Payoff Analysis');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

    final labels = [
      s.navCalculator,
      s.navPayoffPlan,
      s.navDebtStrategy,
      s.navGoals,
      s.navHistory,
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          s.appTitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          CalcwiseAppBarActions(
            freemium: freemiumService,
            session: paywallSession,
            onSettings: () => Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const SettingsScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            ),
            onRewardAd: () => CalcwiseRewardAdSheet.show(context),
            onPremium: () => PaywallHard.show(context),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onTabSelected,
          destinations: List.generate(
            labels.length,
            (i) => NavigationDestination(
              icon: Icon(_iconsOutlined[i]),
              selectedIcon: Icon(_icons[i], color: AppTheme.primary),
              label: labels[i],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoAnimPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

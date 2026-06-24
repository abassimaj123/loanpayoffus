import 'dart:async';
import 'package:calcwise_core/calcwise_core.dart' hide CrashlyticsService, PaywallHard;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
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
import 'core/db/loan_payoff_us_database_adapter.dart';

final paywallSession = PaywallSessionService(
  appKey: 'loanpayoffus',
  hasFullAccess: () => freemiumService.hasFullAccess,
);

/// SmartHistory ring buffer + pinned scenarios service.
final smartHistoryService = SmartHistoryService(
  db: LoanPayoffUSDatabaseAdapter(),
  freemium: freemiumService,
);

/// Bumped to trigger a silent reload of the History screen after a save.
final historyRefreshNotifier = ValueNotifier<int>(0);

/// Bumped after a backup is restored so the Debt Strategy screen reloads its
/// debts + payments from storage (the tab is kept alive in a Stack, so it
/// never re-runs initState on its own).
final debtRefreshNotifier = ValueNotifier<int>(0);

/// AdMob unit IDs. Production IDs are injected at build time via
/// `--dart-define-from-file=admob.json` (see admob.example.json). When a prod
/// ID is missing — or in any non-release build — the Google official TEST units
/// are used so a release build can NEVER ship a placeholder.
class AdConfig {
  AdConfig._();

  // Google official TEST ad unit IDs (debug + release fallback).
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testInterstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';

  // Production IDs injected via --dart-define-from-file=admob.json.
  static const _prodBannerAndroid = String.fromEnvironment('ADMOB_BANNER_ANDROID');
  static const _prodInterstitialAndroid = String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID');
  static const _prodRewardedAndroid = String.fromEnvironment('ADMOB_REWARDED_ANDROID');

  static String get bannerAndroid =>
      kReleaseMode && _prodBannerAndroid.isNotEmpty ? _prodBannerAndroid : _testBannerAndroid;
  static String get interstitialAndroid =>
      kReleaseMode && _prodInterstitialAndroid.isNotEmpty ? _prodInterstitialAndroid : _testInterstitialAndroid;
  static String get rewardedAndroid =>
      kReleaseMode && _prodRewardedAndroid.isNotEmpty ? _prodRewardedAndroid : _testRewardedAndroid;
}

final adService = CalcwiseAdService(
  config: CalcwiseAdConfig(
    bannerAndroid: AdConfig.bannerAndroid,
    interstitialAndroid: AdConfig.interstitialAndroid,
    rewardedAndroid: AdConfig.rewardedAndroid,
  ),
  freemium: freemiumService,
  analytics: AnalyticsService.instance,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load date symbols for all locales so DateFormat('…', 'es'|'en') never throws
  // and month names follow the in-app language, not the device locale.
  await initializeDateFormatting();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  unawaited(CalcwiseRemoteConfig.initialize());
  await CalcwiseTax.init(remoteFetcher: calcwiseTaxRemoteFetch);
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
  if (kDebugMode) {
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: ['FD16D4616C3A21C3ACE5E48F8DC9C1DC']),
    );
  }
  unawaited(AnalyticsService.instance.initialize());
  AnalyticsService.instance.setUserPremium(freemiumService.hasFullAccess);
  await AnalyticsService.instance.logAppOpen();
  CalcwiseAdFooter.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
    onGetPremium: () => IAPService.instance.buy(),
    analytics: AnalyticsService.instance,
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
    iapRestoreResultNotifier.addListener(_onRestoreResult);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordSession());
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    freemiumService.isPremiumNotifier.removeListener(_onPremiumChange);
    iapErrorNotifier.removeListener(_onIapError);
    iapRestoreResultNotifier.removeListener(_onRestoreResult);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  void _onPremiumChange() {
    final now = freemiumService.hasFullAccess;
    if (now && !_wasPremium) {
      AnalyticsService.instance.logPurchaseCompleted();
    }
    if (now && !_wasPremium && mounted) {
      showPremiumWelcomeSnackBar(context, isSpanish: isSpanishNotifier.value);
    }
    _wasPremium = now;
    unawaited(AnalyticsService.instance.setUserPremium(now));
  }

  void _onRestoreResult() {
    final result = iapRestoreResultNotifier.value;
    if (result == null || !mounted) return;
    final isEs = isSpanishNotifier.value;
    final msg = result == 'restored'
        ? (isEs ? '¡Premium restaurado!' : 'Premium restored!')
        : (isEs ? 'No hay compras para restaurar.' : 'No purchases to restore.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
    iapRestoreResultNotifier.value = null;
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
    setState(() => _index = i);
    await AnalyticsService.instance.logTabSwitch(tabName: _tabNames[i]);

    // Don't gate the Calculator tab — it's always free
    if (i == 0) return;

    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    if (trigger == PaywallTrigger.hard) {
      PaywallHard.show(context);
    } else if (trigger == PaywallTrigger.soft) {
      PaywallSoft.show(
        context,
        featureTitle: isSpanishNotifier.value
            ? 'Análisis de Liquidación'
            : 'Full Payoff Analysis',
        isSpanish: isSpanishNotifier.value,
        onUnlock: () => PaywallHard.show(context),
      );
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
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: Text(
          s.appTitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
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
      body: Stack(
        fit: StackFit.expand,
        children: List.generate(
          _screens.length,
          (i) => IgnorePointer(
            ignoring: _index != i,
            child: CalcwiseTabReveal(active: _index == i, child: _screens[i]),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
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

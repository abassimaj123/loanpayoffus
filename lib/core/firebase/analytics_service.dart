import 'package:firebase_analytics/firebase_analytics.dart';

/// Centralises all Firebase Analytics event logging.
/// Every public method is a named event — keep names snake_case ≤ 40 chars.
class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  final _fa = FirebaseAnalytics.instance;

  // ── App lifecycle ────────────────────────────────────────────────────────
  Future<void> logAppOpen() => _fa.logAppOpen();

  Future<void> logSessionStart({required int sessionNumber}) =>
      _fa.logEvent(name: 'session_start', parameters: {'session_number': sessionNumber});

  // ── Calculator ───────────────────────────────────────────────────────────
  Future<void> logCalculation({
    required String loanType,
    required double loanAmount,
    required double interestRate,
    required double extraPayment,
    required int monthsSaved,
    required double interestSaved,
  }) =>
      _fa.logEvent(name: 'loan_calculated', parameters: {
        'loan_type':      loanType,
        'loan_amount':    loanAmount.round(),
        'interest_rate':  interestRate,
        'extra_payment':  extraPayment.round(),
        'months_saved':   monthsSaved,
        'interest_saved': interestSaved.round(),
      });

  // ── Tab navigation ───────────────────────────────────────────────────────
  Future<void> logTabSwitch({required String tabName}) =>
      _fa.logEvent(name: 'tab_switch', parameters: {'tab_name': tabName});

  Future<void> logScreenView({required String screenName}) =>
      _fa.logScreenView(screenName: screenName);

  // ── Paywall funnel ───────────────────────────────────────────────────────
  Future<void> logPaywallShown({required String paywallType}) =>
      _fa.logEvent(name: 'paywall_shown', parameters: {'paywall_type': paywallType});

  Future<void> logPaywallDismissed({required String paywallType}) =>
      _fa.logEvent(name: 'paywall_dismissed', parameters: {'paywall_type': paywallType});

  Future<void> logPurchaseStarted() =>
      _fa.logEvent(name: 'purchase_started');

  Future<void> logPurchaseCompleted() =>
      _fa.logEvent(name: 'purchase_completed');

  Future<void> logPurchaseRestored() =>
      _fa.logEvent(name: 'purchase_restored');

  Future<void> logPurchaseError({required String code}) =>
      _fa.logEvent(name: 'purchase_error', parameters: {'error_code': code});

  // ── Rewarded ad ──────────────────────────────────────────────────────────
  Future<void> logRewardedAdShown() =>
      _fa.logEvent(name: 'rewarded_ad_shown');

  Future<void> logRewardedAdEarned() =>
      _fa.logEvent(name: 'rewarded_ad_earned');

  // ── Goals ────────────────────────────────────────────────────────────────
  Future<void> logGoalSet({required int targetMonths}) =>
      _fa.logEvent(name: 'goal_set', parameters: {'target_months': targetMonths});

  // ── Export ───────────────────────────────────────────────────────────────
  Future<void> logShareTriggered({required String format}) =>
      _fa.logEvent(name: 'share_triggered', parameters: {'format': format});
}

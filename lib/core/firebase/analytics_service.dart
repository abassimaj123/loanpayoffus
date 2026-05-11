import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Centralises all Firebase Analytics event logging.
/// Every public method is a named event — keep names snake_case ≤ 40 chars.
class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  final _fa = FirebaseAnalytics.instance;

  // ── App lifecycle ────────────────────────────────────────────────────────
  Future<void> logAppOpen() => _log('app_open');

  Future<void> logSessionStart({required int sessionNumber}) =>
      _log('session_start', {'session_number': sessionNumber});

  // ── Calculator ───────────────────────────────────────────────────────────
  Future<void> logCalculation({
    required String loanType,
    required double loanAmount,
    required double interestRate,
    required double extraPayment,
    required int monthsSaved,
    required double interestSaved,
  }) =>
      _log('loan_calculated', {
        'loan_type':      loanType,
        'loan_amount':    loanAmount.round(),
        'interest_rate':  interestRate,
        'extra_payment':  extraPayment.round(),
        'months_saved':   monthsSaved,
        'interest_saved': interestSaved.round(),
      });

  Future<void> logSave() => _log('calculation_saved');

  // ── Tab navigation ───────────────────────────────────────────────────────
  Future<void> logTabSwitch({required String tabName}) =>
      _log('tab_switch', {'tab_name': tabName});

  Future<void> logScreenView({required String screenName}) =>
      _fa.logScreenView(screenName: screenName);

  // ── Paywall funnel ───────────────────────────────────────────────────────
  Future<void> logPaywallShown({required String paywallType}) =>
      _log('paywall_shown', {'paywall_type': paywallType});

  Future<void> logPaywallDismissed({required String paywallType}) =>
      _log('paywall_dismissed', {'paywall_type': paywallType});

  Future<void> logPurchaseStarted() => _log('purchase_started');

  Future<void> logPurchaseCompleted() => _log('purchase_completed');

  Future<void> logPurchaseRestored() => _log('purchase_restored');

  Future<void> logPurchaseError({required String code}) =>
      _log('purchase_error', {'error_code': code});

  // ── Rewarded ad ──────────────────────────────────────────────────────────
  Future<void> logRewardedAdShown() => _log('rewarded_ad_shown');

  Future<void> logRewardedAdEarned() => _log('rewarded_ad_earned');

  // ── Goals ────────────────────────────────────────────────────────────────
  Future<void> logGoalSet({required int targetMonths}) =>
      _log('goal_set', {'target_months': targetMonths});

  // ── Export ───────────────────────────────────────────────────────────────
  Future<void> logShareTriggered({required String format}) =>
      _log('share_triggered', {'format': format});

  // ── Error & limit tracking ──────────────────────────────────────────────
  Future<void> logRewardedAdFailed() => _log('rewarded_ad_failed');
  Future<void> logRewardedDailyLimit() => _log('rewarded_daily_limit_reached');
  Future<void> logPurchaseFailed() => _log('purchase_failed');
  Future<void> logBannerFailed() => _log('banner_ad_failed');

  // ── Internals ────────────────────────────────────────────────────────────
  Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (kDebugMode) {
      debugPrint('[Analytics] $name ${params ?? ''}');
      return;
    }
    await _fa.logEvent(
      name: name,
      parameters: {'app_name': 'LoanPayoffUS', ...?params},
    );
  }

}

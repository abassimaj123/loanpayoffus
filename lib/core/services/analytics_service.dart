import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Centralized Firebase Analytics wrapper for LoanPayoffUS.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _fa = FirebaseAnalytics.instance;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> logAppOpen() => _log('app_open');

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> logTabChanged(String tabName) => _log('tab_changed', {
    'tab': tabName, // calculator|schedule|extra_payment|compare
  });

  // ── Calculator ────────────────────────────────────────────────────────────

  Future<void> logCalculation({
    required double balance,
    required double rate,
    required String strategy, // avalanche|snowball|fixed_extra
  }) => _log('calculate', {
    'balance_bucket': _balanceBucket(balance),
    'rate_bucket':    rate < 5 ? '<5%' : rate < 10 ? '5-10%' : '>10%',
    'strategy':       strategy,
  });

  // ── Paywall ───────────────────────────────────────────────────────────────

  Future<void> logPaywallShown(String type) => _log('paywall_shown', {'type': type});
  Future<void> logPurchaseStarted()         => _log('purchase_started');

  Future<void> logPurchaseCompleted() async {
    await _log('purchase_completed');
    await _fa.logEvent(name: 'purchase', parameters: {
      'currency': 'USD',
      'value':    2.99,
      'items':    'premium_loan_payoff_us',
    });
  }

  Future<void> logPurchaseRestored()   => _log('purchase_restored');
  Future<void> logPurchaseFailed()     => _log('purchase_failed');
  Future<void> logRewardedAdWatched()  => _log('rewarded_ad_watched');

  // ── Features ─────────────────────────────────────────────────────────────

  Future<void> logPdfExported()           => _log('pdf_exported');
  Future<void> logExtraPaymentSimulated() => _log('extra_payment_simulated');
  Future<void> logDebtFreeProjected()     => _log('debt_free_date_projected');
  Future<void> logHistorySaved()          => _log('history_saved');

  // ── User property ─────────────────────────────────────────────────────────

  Future<void> setUserPremium(bool isPremium) =>
      _fa.setUserProperty(name: 'is_premium', value: isPremium ? 'true' : 'false');

  // ── Error & limit tracking ────────────────────────────────────────────────

  Future<void> logRewardedAdFailed() => _log('rewarded_ad_failed');
  Future<void> logPaywallDismissed() => _log('paywall_dismissed');
  Future<void> logBannerFailed()     => _log('banner_ad_failed');

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    final merged = <String, Object>{'app_name': 'LoanPayoffUS', ...?params};
    if (kDebugMode) {
      debugPrint('[Analytics] $name $merged');
      return;
    }
    await _fa.logEvent(name: name, parameters: merged);
  }

  String _balanceBucket(double balance) {
    if (balance < 5000)   return '<5k';
    if (balance < 15000)  return '5-15k';
    if (balance < 50000)  return '15-50k';
    if (balance < 100000) return '50-100k';
    return '>100k';
  }
}

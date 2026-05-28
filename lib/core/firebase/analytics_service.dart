import 'package:calcwise_core/calcwise_core.dart';

/// Firebase Analytics wrapper for LoanPayoffUS.
/// Common events inherited from CalcwiseAnalytics.
/// LoanPayoffUS-specific events (loan_calculated, goal, session, share) kept here.
class AnalyticsService extends CalcwiseAnalytics {
  AnalyticsService._() : super(appName: 'LoanPayoffUS');
  static final AnalyticsService instance = AnalyticsService._();

  // ── Calculator (rich params) ──────────────────────────────────────────────

  Future<void> logCalculation({
    required String loanType,
    required double loanAmount,
    required double interestRate,
    required double extraPayment,
    required int monthsSaved,
    required double interestSaved,
  }) => log('loan_calculated', {
    'loan_type': loanType,
    'loan_amount': loanAmount.round(),
    'interest_rate': interestRate,
    'extra_payment': extraPayment.round(),
    'months_saved': monthsSaved,
    'interest_saved': interestSaved.round(),
  });

  Future<void> logSave() => log('calculation_saved');

  // ── App-specific features ─────────────────────────────────────────────────

  Future<void> logSessionStart({required int sessionNumber}) =>
      log('session_start', {'session_number': sessionNumber});

  Future<void> logTabSwitch({required String tabName}) =>
      log('tab_switch', {'tab_name': tabName});

  Future<void> logGoalSet({required int targetMonths}) =>
      log('goal_set', {'target_months': targetMonths});

  Future<void> logShareTriggered({required String format}) =>
      log('share_triggered', {'format': format});

  Future<void> logPurchaseError({required String code}) =>
      log('purchase_error', {'error_code': code});

  // ── Paywall variants ──────────────────────────────────────────────────────

  /// Override: LoanPayoffUS paywall dismissed carries a type param.
  Future<void> logPaywallDismissedTyped({required String paywallType}) =>
      log('paywall_dismissed', {'paywall_type': paywallType});

  Future<void> logPaywallShownTyped({required String paywallType}) =>
      log('paywall_shown', {'paywall_type': paywallType});

  // ── Canonical taxonomy + LoanPayoffUS-specific ───────────────────────────

  Future<void> logCalculationCompleted({Map<String, Object>? params}) =>
      log('calculation_completed', params);
  Future<void> logResultSaved() => log('result_saved');
  Future<void> logResultShared() => log('result_shared');
  Future<void> logPaywallViewed(String trigger) =>
      log('paywall_viewed', {'trigger': trigger});
  Future<void> logPaywallConverted(String source) =>
      log('paywall_converted', {'source': source});

  Future<void> logDebtAdded({required double balance, required double rate}) =>
      log('debt_added', {'balance': balance, 'rate': rate});
  Future<void> logPaymentLogged({required double amount}) =>
      log('payment_logged', {'amount': amount});
  Future<void> logStrategySelected({required String strategy}) =>
      log('strategy_selected', {'strategy': strategy});

  // ── Universal events (Phase 2) ────────────────────────────────────────────

  Future<void> logScreenView(String screenName) =>
      log('screen_view', {'screen_name': screenName});
  Future<void> logOnboardingComplete() => log('onboarding_complete');
  Future<void> logOnboardingSkipped() => log('onboarding_skipped');
  Future<void> logFirstCalculate() => log('first_calculate');
  Future<void> logDarkModeToggled(bool enabled) =>
      log('dark_mode_toggled', {'enabled': '$enabled'});
  Future<void> logLanguageChanged(String lang) =>
      log('language_changed', {'language': lang});
  Future<void> logShareTapped() => log('share_tapped');
  Future<void> logExportStarted() => log('export_started');
  Future<void> logUpgradeButtonTapped(String source) =>
      log('upgrade_tapped', {'source': source});
  Future<void> logFeatureGated(String feature) =>
      log('feature_gated', {'feature': feature});

  // ── LoanPayoffUS domain events (Phase 2) ─────────────────────────────────

  Future<void> logDebtStrategySelected(String strategy) =>
      log('debt_strategy_selected', {'strategy': strategy});
  Future<void> logExtraPaymentImpact() => log('extra_payment_impact');
  Future<void> logDebtFreeProjected(int months) =>
      log('debt_free_projected', {'months': months});
  Future<void> logNewDebtAdded() => log('new_debt_added');
}

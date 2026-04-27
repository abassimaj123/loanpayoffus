import 'package:shared_preferences/shared_preferences.dart';
import 'freemium_service.dart';

/// Paywall gate logic:
///   Sessions 1–3  → free, no paywall
///   Sessions 4–6  → soft paywall (dismissible)
///   Sessions 7+   → hard paywall (rewarded + IAP only)
///
/// Calculations: soft every 5 calcs, hard every 10 calcs.
final paywallService = PaywallService._();

enum PaywallGate { none, soft, hard }

class PaywallService {
  PaywallService._();

  static const _keySessionCount = 'paywall_session_count';
  static const _keyCalcCount    = 'paywall_calc_count';

  int _sessionCount = 0;
  int _calcCount    = 0;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCount = prefs.getInt(_keySessionCount) ?? 0;
    _calcCount    = prefs.getInt(_keyCalcCount)    ?? 0;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySessionCount, _sessionCount);
    await prefs.setInt(_keyCalcCount,    _calcCount);
  }

  /// Call once at app start. Returns the gate to show (none/soft/hard).
  Future<PaywallGate> recordSession() async {
    if (freemiumService.isPremium) return PaywallGate.none;
    _sessionCount++;
    await _save();
    if (_sessionCount >= 7) return PaywallGate.hard;
    if (_sessionCount >= 4) return PaywallGate.soft;
    return PaywallGate.none;
  }

  /// Call on every calculation AND every tab switch.
  /// Returns the gate to show (none/soft/hard).
  Future<PaywallGate> recordAction() async {
    if (freemiumService.isPremium) return PaywallGate.none;
    _calcCount++;
    await _save();
    // Hard gate: every 10 actions when in session 7+
    if (_sessionCount >= 7 && _calcCount % 10 == 0) return PaywallGate.hard;
    // Soft gate: every 5 actions when in sessions 4–6
    if (_sessionCount >= 4 && _calcCount % 5 == 0)  return PaywallGate.soft;
    return PaywallGate.none;
  }

  void resetCalcCount() => _calcCount = 0;

  int get sessionCount => _sessionCount;
  int get calcCount    => _calcCount;
}

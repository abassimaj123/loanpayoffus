import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final freemiumService = FreemiumService._();

class FreemiumService {
  FreemiumService._();

  static const _keyPremium  = 'is_premium';
  static const _keyRewarded = 'rewarded_until';
  static const int freeHistoryLimit = 100;
  static const int rewardedMinutes  = 60;

  late SharedPreferences _prefs;

  final isPremiumNotifier  = ValueNotifier<bool>(false);
  final isRewardedNotifier = ValueNotifier<bool>(false);

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    isPremiumNotifier.value = _prefs.getBool(_keyPremium) ?? false;
    _refreshRewarded();
  }

  void _refreshRewarded() {
    final s = _prefs.getString(_keyRewarded);
    isRewardedNotifier.value =
        s != null && DateTime.now().isBefore(DateTime.parse(s));
  }

  bool get isPremium  => isPremiumNotifier.value;
  bool get isRewarded { _refreshRewarded(); return isRewardedNotifier.value; }

  /// True when ads (banner + interstitial) should be displayed.
  bool get showAds => !isPremium && !isRewarded;

  /// Max number of history entries for free users.
  int get historyLimit => isPremium ? 999999 : freeHistoryLimit;

  int get rewardedMinutesLeft {
    _refreshRewarded();
    if (!isRewardedNotifier.value) return 0;
    final s = _prefs.getString(_keyRewarded)!;
    return DateTime.parse(s)
        .difference(DateTime.now())
        .inMinutes
        .clamp(0, rewardedMinutes);
  }

  Future<void> activateRewarded() async {
    await _prefs.setString(
      _keyRewarded,
      DateTime.now()
          .add(const Duration(minutes: rewardedMinutes))
          .toIso8601String(),
    );
    isRewardedNotifier.value = true;
  }

  Future<void> activatePremium() async {
    isPremiumNotifier.value = true;
    await _prefs.setBool(_keyPremium, true);
  }

  /// DEV only — force premium without IAP (remove before release).
  void debugUnlockPremium() {
    if (kDebugMode) activatePremium();
  }
}

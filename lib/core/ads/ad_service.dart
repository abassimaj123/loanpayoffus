import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../freemium/freemium_service.dart';

class AdService {
  AdService._();
  static final AdService instance = AdService._();

  // TODO: Replace with real AdMob IDs before publishing to Play Store
  static const bannerId       = 'ca-app-pub-3940256099942544/6300978111';
  static const interstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const rewardedId     = 'ca-app-pub-3940256099942544/5224354917';

  int _calcCount = 0;
  DateTime?       _lastInterstitial;
  InterstitialAd? _interstitial;
  RewardedAd?     _rewarded;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (err) {
          _interstitial = null;
          debugPrint('Interstitial failed: $err');
        },
      ),
    );
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  void onCalculation() {
    if (!freemiumService.showAds) return;
    _calcCount++;
    final now = DateTime.now();
    if (_calcCount % 5 == 0 &&
        (_lastInterstitial == null ||
            now.difference(_lastInterstitial!).inMinutes >= 5)) {
      _lastInterstitial = now;
      _interstitial?.show();
      _interstitial = null;
      _loadInterstitial();
    }
  }

  Future<bool> showRewarded() async {
    if (_rewarded == null) return false;
    bool earned = false;
    final completer = Completer<bool>();
    _rewarded!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        _rewarded = null;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (_, __) {
        _rewarded = null;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    _rewarded!.show(onUserEarnedReward: (_, __) => earned = true);
    return completer.future;
  }
}

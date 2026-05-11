import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';
import '../freemium/freemium_service.dart';
import '../firebase/analytics_service.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});
  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _retried = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _ad = BannerAd(
      adUnitId: AdService.bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) { if (mounted) setState(() => _loaded = true); },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (!mounted) return;
          setState(() { _ad = null; _loaded = false; });
          AnalyticsService.instance.logBannerFailed();
          if (!_retried) {
            _retried = true;
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) _load();
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() { _ad?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (_, isPremium, child) {
        if (isPremium) return const SizedBox.shrink();
        if (!_loaded || _ad == null) return const SizedBox(height: 50);
        return SizedBox(height: 50, child: AdWidget(ad: _ad!));
      },
    );
  }
}

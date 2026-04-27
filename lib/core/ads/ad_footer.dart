import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';
import '../freemium/freemium_service.dart';
import '../freemium/iap_service.dart';

/// Universal monetization footer — replaces BannerAdWidget in every screen.
///
/// Premium  → nothing
/// Rewarded → green ad-free timer only (no banner)
/// Free     → "Watch ad" button + banner ad
class AdFooter extends StatefulWidget {
  const AdFooter({super.key});
  @override
  State<AdFooter> createState() => _AdFooterState();
}

class _AdFooterState extends State<AdFooter> {
  BannerAd? _banner;
  bool      _bannerLoaded = false;
  Timer?    _tick;

  @override
  void initState() {
    super.initState();
    freemiumService.isPremiumNotifier.addListener(_rebuild);
    freemiumService.isRewardedNotifier.addListener(_rebuild);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    if (freemiumService.showAds) _loadBanner();
  }

  @override
  void dispose() {
    freemiumService.isPremiumNotifier.removeListener(_rebuild);
    freemiumService.isRewardedNotifier.removeListener(_rebuild);
    _tick?.cancel();
    _banner?.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
    // Load banner lazily when user loses premium/rewarded
    if (freemiumService.showAds && _banner == null) _loadBanner();
  }

  void _loadBanner() {
    _banner = BannerAd(
      adUnitId: AdService.bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() { _banner = ad as BannerAd; _bannerLoaded = true; });
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    // ── Premium: no ads, no UI ──────────────────────────────────────────────
    if (freemiumService.isPremium) return const SizedBox.shrink();

    // ── Rewarded active: timer banner only ──────────────────────────────────
    if (freemiumService.isRewarded) {
      final mins = freemiumService.rewardedMinutesLeft;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.green.shade50,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.timer_outlined, size: 15, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text('Ad-free — $mins min remaining',
              style: TextStyle(
                  color: Colors.green.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      );
    }

    // ── Free tier: watch-ad button + banner ─────────────────────────────────
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _WatchAdRow(),
      if (_bannerLoaded && _banner != null)
        SizedBox(
          width: double.infinity,
          height: _banner!.size.height.toDouble(),
          child: AdWidget(ad: _banner!),
        ),
    ]);
  }
}

// ── Watch-ad button ───────────────────────────────────────────────────────────
class _WatchAdRow extends StatefulWidget {
  @override
  State<_WatchAdRow> createState() => _WatchAdRowState();
}

class _WatchAdRowState extends State<_WatchAdRow> {
  bool _loading = false;

  Future<void> _watch() async {
    setState(() => _loading = true);
    final earned = await AdService.instance.showRewarded();
    if (earned) await freemiumService.activateRewarded();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      color: Colors.grey.shade50,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TextButton.icon(
          onPressed: _loading ? null : _watch,
          icon: _loading
              ? const SizedBox(
                  width: 13, height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.play_circle_outline, size: 16, color: primary),
          label: Text(
            _loading ? 'Loading…' : 'Watch ad → 60min ad-free',
            style: TextStyle(fontSize: 11, color: primary),
          ),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
        ),
        TextButton(
          onPressed: () => IAPService.instance.buy(),
          child: Text('Get Premium',
              style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.bold)),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
        ),
      ]),
    );
  }
}

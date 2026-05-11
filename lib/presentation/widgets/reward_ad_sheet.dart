import 'dart:async';
import '../../core/language/language_notifier.dart';
import 'package:flutter/material.dart';
import '../../core/ads/ad_service.dart';
import '../../core/freemium/freemium_service.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart';

/// Bottom sheet: watch a rewarded ad for 60 min ad-free access.
class RewardAdSheet extends StatefulWidget {
  const RewardAdSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const RewardAdSheet(),
  );

  @override
  State<RewardAdSheet> createState() => _RewardAdSheetState();
}

class _RewardAdSheetState extends State<RewardAdSheet> {
  bool _loading = false;
  Timer? _timer;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = freemiumService.rewardedRemaining;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _remaining = freemiumService.rewardedRemaining);
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final adReady = AdService.instance.isRewardedReady;
    final isAdFree = _remaining != null && _remaining!.inSeconds > 0;
    final isSpanish = isSpanishNotifier.value;

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: const Color(0xFFCBD5E1),
            borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Container(width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle),
          child: Icon(isAdFree ? Icons.shield : Icons.shield_outlined,
            size: 34, color: AppTheme.primary)),
        const SizedBox(height: 16),
        Text(isSpanish ? 'Modo sin anuncios' : 'Ad-Free Mode',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (isAdFree && _remaining != null)
          _StatusChip(label: isSpanish
              ? 'Sin anuncios: ${_remaining!.inMinutes}m ${_remaining!.inSeconds.remainder(60)}s restantes'
              : 'Ad-free: ${_remaining!.inMinutes}m ${_remaining!.inSeconds.remainder(60)}s remaining')
        else
          Text(isSpanish
              ? 'Mira un video corto para 60 min sin anuncios'
              : 'Watch a short video for 60 min ad-free',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF475569), height: 1.4)),
        const SizedBox(height: 24),
        Opacity(opacity: adReady ? 1.0 : 0.45,
          child: InkWell(
            onTap: (adReady && !_loading) ? _watchAd : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: adReady
                  ? AppTheme.primary.withValues(alpha: 0.35)
                  : const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.play_circle_outline,
                    color: AppTheme.primary, size: 24)),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(isSpanish ? 'Ver un video corto' : 'Watch a short video',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      if (isAdFree) ...[
                        const SizedBox(width: 8),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10)),
                          child: Text(isSpanish ? 'Activo' : 'Active',
                            style: const TextStyle(color: Color(0xFF16A34A), fontSize: 11,
                              fontWeight: FontWeight.w600))),
                      ]
                    ]),
                    const SizedBox(height: 2),
                    Text(isSpanish ? '60 min sin anuncios' : '60 min ad-free',
                      style: const TextStyle(color: Color(0xFF475569), fontSize: 13)),
                  ])),
                if (_loading)
                  const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                else
                  const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
              ]),
            ))),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isSpanish ? 'Más tarde' : 'Maybe later',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
      ]),
    );
  }

  Future<void> _watchAd() async {
    setState(() => _loading = true);
    final earned = await AdService.instance.showRewarded();
    if (!mounted) return;
    final isSpanish = isSpanishNotifier.value;
    setState(() => _loading = false);
    if (earned) {
      await freemiumService.activateRewarded();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isSpanish
            ? 'Modo sin anuncios activado — 60 min'
            : 'Ad-free mode activated — 60 min'),
        backgroundColor: const Color(0xFF16A34A)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isSpanish
            ? 'Anuncio no disponible. Inténtalo más tarde.'
            : 'Ad not available. Try again later.')));
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  const _StatusChip({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF16A34A).withValues(alpha: 0.12),
      border: Border.all(color: const Color(0xFF16A34A)),
      borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: const TextStyle(
      color: Color(0xFF16A34A), fontWeight: FontWeight.w600, fontSize: 13)));
}

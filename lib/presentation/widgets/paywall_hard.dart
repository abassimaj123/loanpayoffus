import 'package:flutter/material.dart';
import '../../core/freemium/iap_service.dart';
import '../../core/freemium/freemium_service.dart';
import '../../core/ads/ad_service.dart';
import '../../core/firebase/analytics_service.dart';
import '../../core/language/language_notifier.dart';

class PaywallHard extends StatelessWidget {
  const PaywallHard({super.key});

  static Future<void> show(BuildContext context) async {
    await AnalyticsService.instance.logPaywallShown(paywallType: 'hard');
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PaywallHard(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, isSpanish, __) {
        final title = isSpanish
            ? 'Deja de pagar intereses de más'
            : 'Stop overpaying interest on your loans';
        final sub = isSpanish
            ? 'Premium te muestra exactamente cómo ahorrar'
            : 'Premium shows exactly how to save more';
        final features = isSpanish
            ? ['💰 Compara estrategias de pago',
                '📉 Calcula el ahorro exacto en intereses',
                '📊 Historial ilimitado & PDF',
                '🚫 Sin anuncios — nunca']
            : ['💰 Compare payoff strategies side by side',
                '📉 See exact interest savings',
                '📊 Unlimited history & PDF export',
                '🚫 Zero ads — ever'];
        const price    = r'$2.99';
        const savings  = r'(save $100+)';
        final btnPrimary = isSpanish
            ? 'Empezar a ahorrar\n$price (ahorra \$100+)'
            : 'Start saving now\n$price $savings';
        final btnReward    = isSpanish ? 'Ver anuncio (60 min gratis)' : 'Watch ad (60 min free)';
        // Hard dismiss = "Not now" / "Ahora no" at Opacity 0.5
        final btnSecondary = isSpanish ? 'Ahora no' : 'Not now';

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: Colors.orange, size: 32),
                ),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 18),
                ...features.map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        const SizedBox(width: 8),
                        Expanded(child: Text(f, style: const TextStyle(fontSize: 14))),
                      ]),
                    )),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      IAPService.instance.buy();
                    },
                    child: Text(btnPrimary,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, height: 1.4)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      AnalyticsService.instance.logRewardedAdShown();
                      final earned = await AdService.instance.showRewarded();
                      if (earned) {
                        freemiumService.activateRewarded();
                        AnalyticsService.instance.logRewardedAdEarned();
                      }
                    },
                    child: Text(btnReward, style: const TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 4),
                // Hard dismiss = Opacity 0.5 to discourage, label "Not now" / "Ahora no"
                Opacity(
                  opacity: 0.5,
                  child: TextButton(
                    onPressed: () {
                      AnalyticsService.instance
                          .logPaywallDismissed(paywallType: 'hard');
                      Navigator.pop(context);
                    },
                    child: Text(btnSecondary,
                        style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

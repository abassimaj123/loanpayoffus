/// Thin wrapper — delegates to calcwise_core's PaywallHard.
/// Keeps the same API so no screen files need to change.
import 'package:calcwise_core/calcwise_core.dart' as cw;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart';
import '../../core/freemium/iap_service.dart';
import '../../core/language/language_notifier.dart' show isSpanishNotifier;

class PaywallHard extends StatelessWidget {
  const PaywallHard({super.key});

  /// Forward the localized price to calcwise_core's global price notifier.
  static void registerPrice(ValueNotifier<String?> priceNotifier) {
    cw.PaywallHard.registerPrice(priceNotifier);
  }

  static Future<void> show(BuildContext context) {
    final isSpanish = isSpanishNotifier.value;
    return cw.PaywallHard.show(
      context,
      isSpanish: isSpanish,
      onPurchase: IAPService.instance.buy,
      onWatchAd: () => cw.CalcwiseRewardAdSheet.show(context),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

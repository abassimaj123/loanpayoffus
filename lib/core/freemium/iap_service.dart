import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'freemium_service.dart';
import '../firebase/analytics_service.dart';
import '../review/review_service.dart';

class IAPService {
  IAPService._();
  static final instance = IAPService._();

  /// Must match the product ID created in Google Play Console.
  static const productId = 'premium_upgrade';

  /// Surfaced to UI via Snackbar — emits error message or null.
  final iapErrorNotifier = ValueNotifier<String?>(null);

  StreamSubscription<List<PurchaseDetails>>? _sub;

  Future<void> initialize() async {
    _sub = InAppPurchase.instance.purchaseStream.listen(_handlePurchases);
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('IAP restore error: $e');
    }
  }

  /// Initiate the purchase flow with 10-second timeout.
  Future<void> buy() async {
    iapErrorNotifier.value = null;
    try {
      final available = await InAppPurchase.instance.isAvailable()
          .timeout(const Duration(seconds: 10));
      if (!available) {
        iapErrorNotifier.value = 'Purchases not available on this device';
        return;
      }

      final response = await InAppPurchase.instance
          .queryProductDetails({productId})
          .timeout(const Duration(seconds: 10));

      if (response.productDetails.isEmpty) {
        iapErrorNotifier.value = 'Product not found — try again later';
        debugPrint('IAP product not found: $productId — check Play Console');
        return;
      }

      await AnalyticsService.instance.logPurchaseStarted();
      final param = PurchaseParam(productDetails: response.productDetails.first);
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    } on TimeoutException {
      iapErrorNotifier.value = 'Purchase timed out — check your connection';
    } catch (e) {
      iapErrorNotifier.value = 'Purchase error: ${e.toString()}';
      debugPrint('IAP buy error: $e');
    }
  }

  /// Restore a previous purchase (required for Google Play policy).
  Future<void> restore() async {
    iapErrorNotifier.value = null;
    try {
      await InAppPurchase.instance.restorePurchases()
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      iapErrorNotifier.value = 'Restore timed out — check your connection';
    } catch (e) {
      iapErrorNotifier.value = 'Restore error: ${e.toString()}';
      debugPrint('IAP restore error: $e');
    }
  }

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      if (p.productID == productId) {
        if (p.status == PurchaseStatus.purchased ||
            p.status == PurchaseStatus.restored) {
          freemiumService.activatePremium();
          if (p.status == PurchaseStatus.purchased) {
            AnalyticsService.instance.logPurchaseCompleted();
            // Trigger in-app review after successful purchase
            ReviewService.instance.requestAfterPurchase();
          } else {
            AnalyticsService.instance.logPurchaseRestored();
          }
          debugPrint('Premium activated');
        } else if (p.status == PurchaseStatus.error) {
          final code = p.error?.code ?? 'unknown';
          iapErrorNotifier.value = 'Purchase failed (${p.error?.message ?? code})';
          AnalyticsService.instance.logPurchaseError(code: code);
          debugPrint('IAP error: ${p.error}');
        }
        if (p.pendingCompletePurchase) {
          InAppPurchase.instance.completePurchase(p);
        }
      }
    }
  }

  void dispose() => _sub?.cancel();
}

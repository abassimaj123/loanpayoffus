import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

/// Triggers an in-app review prompt after IAP purchase.
/// Respects Play Store rate-limit (silent no-op if quota exceeded).
class ReviewService {
  ReviewService._();
  static final instance = ReviewService._();

  Future<void> requestAfterPurchase() async {
    try {
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
      }
    } catch (e) {
      debugPrint('ReviewService: $e');
    }
  }
}

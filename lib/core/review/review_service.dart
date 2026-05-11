import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  ReviewService._();
  static final instance = ReviewService._();

  static const _keyLastShown  = 'review_last_ms';
  static const _keySaveCount  = 'review_save_count';
  static const int _saveThreshold  = 3;
  static const int _minDaysBetween = 90;

  /// Call after every successful save. Shows review dialog on the 3rd save,
  /// then at most once every 90 days thereafter.
  Future<void> requestAfterSave() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_keySaveCount) ?? 0) + 1;
    await prefs.setInt(_keySaveCount, count);
    if (count >= _saveThreshold) {
      await _maybeRequest(prefs);
    }
  }

  /// Direct user-initiated request (e.g. "Rate App" button in Settings).
  Future<void> requestAfterPurchase() async {
    final prefs = await SharedPreferences.getInstance();
    await _maybeRequest(prefs);
  }

  /// Opens the store listing directly — used in Settings "Rate App" row.
  Future<void> openStoreForReview() async {
    try {
      await InAppReview.instance.openStoreListing();
    } catch (e) {
      debugPrint('ReviewService.openStoreForReview: $e');
    }
  }

  Future<void> _maybeRequest(SharedPreferences prefs) async {
    final lastMs = prefs.getInt(_keyLastShown);
    if (lastMs != null) {
      final daysSince =
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastMs)).inDays;
      if (daysSince < _minDaysBetween) return;
    }
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
        await prefs.setInt(_keyLastShown, DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt(_keySaveCount, 0);
      }
    } catch (e) {
      debugPrint('ReviewService: $e');
    }
  }
}

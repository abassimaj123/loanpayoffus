import 'package:flutter/material.dart';
import '../../core/freemium/freemium_service.dart';
import 'paywall_soft.dart';
import 'package:calcwise_core/calcwise_core.dart';

/// AppBar action widget that shows "Premium" badge when active,
/// or a "⭐ Go Pro" tap-to-upgrade chip when free.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (context, isPremium, _) {
        if (isPremium) {
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smPlus,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, color: Colors.amber, size: 13),
                    SizedBox(width: AppSpacing.xs),
                    Text(
                      'Premium',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: Center(
            child: GestureDetector(
              onTap: () => PaywallSoft.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smPlus,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_outline_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                    SizedBox(width: AppSpacing.xs),
                    Text(
                      'Go Pro',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

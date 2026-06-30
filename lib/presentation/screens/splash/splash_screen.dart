import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/language/language_notifier.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatelessWidget {
  final Widget child;
  const SplashScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    return CalcwiseSplash(
    appName: 'Loan Payoff',
    appSuffix: 'US',
    tagline: isEs ? 'Liquida tu deuda más rápido' : 'Crush your debt faster',
    chips: isEs
        ? const ['Pagos Extra', 'Avalancha', 'Bola de Nieve']
        : const ['Extra Payments', 'Avalanche', 'Snowball'],
    badgeIcon: Icons.account_balance_wallet_rounded,
    backgroundColor: AppTheme.primary,
    onComplete: () async {
      final done = await isOnboardingComplete('loanpayoffus');
      if (!context.mounted) return;
      if (!done) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => OnboardingScreen(child: child),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: AppDuration.base,
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => child,
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: AppDuration.base,
          ),
        );
      }
    },
  );
  }
}

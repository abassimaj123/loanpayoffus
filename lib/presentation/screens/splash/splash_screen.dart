import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/firebase/analytics_service.dart';

class SplashScreen extends StatefulWidget {
  final Widget child;
  const SplashScreen({super.key, required this.child});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    try {
      AnalyticsService.instance.logAppOpen();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => CalcwiseSplash(
        appName: 'Loan Payoff',
        appSuffix: 'US',
        tagline: 'Crush your debt faster',
        chips: const ['Extra Payments', 'Avalanche', 'Snowball'],
        badgeSymbol: r'L$',
        badgeIcon: Icons.account_balance_rounded,
        backgroundColor: AppTheme.primary,
        onComplete: () => Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => widget.child,
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 250),
            reverseTransitionDuration: const Duration(milliseconds: 200),
          ),
        ),
      );
}

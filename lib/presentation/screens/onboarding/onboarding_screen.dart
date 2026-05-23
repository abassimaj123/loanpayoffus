import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

class OnboardingScreen extends StatelessWidget {
  final Widget child;
  const OnboardingScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) => CalcwiseOnboarding(
    appKey: 'loanpayoffus',
    nextScreen: child,
    pages: const [
      OnboardingPage(
        icon: Icons.savings_rounded,
        title: 'Crush Your\nDebt Faster',
        subtitle:
            'See exactly when you\'ll be debt-free — with or without extra payments.',
        pills: ['Extra Payments', 'Avalanche', 'Snowball'],
        titleFr: 'Remboursez vos\ndettes plus vite',
        subtitleFr: 'Voyez exactement quand vous serez libéré de vos dettes.',
        pillsFr: ['Paiements extra', 'Avalanche', 'Boule de neige'],
        titleEs: 'Paga tus\ndeudas más rápido',
        subtitleEs:
            'Ve exactamente cuándo estarás libre de deudas — con o sin pagos extra.',
        pillsEs: ['Pagos extra', 'Avalancha', 'Bola de nieve'],
      ),
      OnboardingPage(
        icon: Icons.ac_unit_rounded,
        title: 'Pick Your\nPayoff Strategy',
        subtitle:
            'Avalanche saves the most interest. Snowball keeps you motivated. You choose.',
        pills: ['Avalanche', 'Snowball', 'Custom'],
        titleFr: 'Choisissez votre\nstratégie',
        subtitleFr:
            'Avalanche économise le plus. Boule de neige garde la motivation. Vous choisissez.',
        pillsFr: ['Avalanche', 'Boule de neige', 'Personnalisé'],
        titleEs: 'Elige tu\nestrategia',
        subtitleEs:
            'Avalancha ahorra más intereses. Bola de nieve mantiene la motivación. Tú eliges.',
        pillsEs: ['Avalancha', 'Bola de nieve', 'Personalizado'],
      ),
      OnboardingPage(
        icon: Icons.timeline_rounded,
        title: 'Track Your\nDebt Journey',
        subtitle:
            'Save your payoff plans and watch your progress toward being debt-free.',
        pills: ['History', 'PDF Export', 'Share'],
        titleFr: 'Suivez votre\nparcours sans dettes',
        subtitleFr:
            'Sauvegardez vos plans et suivez vos progrès vers la liberté financière.',
        pillsFr: ['Historique', 'Export PDF', 'Partager'],
        titleEs: 'Sigue tu\nrecorrido sin deudas',
        subtitleEs:
            'Guarda tus planes y sigue tu progreso hacia la libertad financiera.',
        pillsEs: ['Historial', 'Exportar PDF', 'Compartir'],
      ),
    ],
  );
}

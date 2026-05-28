import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import '../../core/language/language_notifier.dart';
import '../../core/services/streak_service.dart';
import '../../core/theme/app_theme.dart';
import '../screens/debt_strategy/payments_history_screen.dart';

class StreakCard extends StatefulWidget {
  const StreakCard({super.key});

  @override
  State<StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<StreakCard> {
  int _streak = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStreak();
    isSpanishNotifier.addListener(_onLang);
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLang);
    super.dispose();
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStreak() async {
    final s = await StreakService.computeStreak();
    if (mounted) {
      setState(() {
        _streak = s;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    final isEs = isSpanishNotifier.value;
    final streak = _streak;

    final IconData icon;
    final Color iconColor;
    final String message;

    if (streak == 0) {
      icon = Icons.local_fire_department_outlined;
      iconColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
      message = isEs
          ? '¡Comienza tu racha! Registra tu primer pago este mes.'
          : 'Start your streak! Log your first payment this month.';
    } else if (streak >= 6) {
      icon = Icons.emoji_events_rounded;
      iconColor = const Color(0xFFFFD700); // gold
      message = isEs
          ? '🏆 $streak ${streak == 1 ? 'mes' : 'meses'} de racha — ¡disciplina increíble!'
          : '🏆 $streak month streak — incredible discipline!';
    } else if (streak >= 3) {
      icon = Icons.local_fire_department_rounded;
      iconColor = Colors.amber;
      message = isEs
          ? '🔥 $streak ${streak == 1 ? 'mes' : 'meses'} de racha — ¡estás en llamas!'
          : '🔥 $streak month streak — you\'re on fire!';
    } else {
      // streak == 1 or 2
      icon = Icons.local_fire_department_rounded;
      iconColor = Colors.amber;
      message = isEs
          ? '🔥 $streak ${streak == 1 ? 'mes' : 'meses'} de racha — ¡sigue así!'
          : '🔥 $streak month streak — keep it going!';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.mdPlus),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: streak == 0 ? FontWeight.normal : FontWeight.w600,
                color: streak == 0
                    ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PaymentsHistoryScreen(),
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Text(
              isEs ? 'Ver Pagos' : 'Log Payment',
              style: const TextStyle(fontSize: AppTextSize.xs),
            ),
          ),
        ],
      ),
    );
  }
}

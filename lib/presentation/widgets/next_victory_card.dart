import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import '../../core/language/language_notifier.dart';
import '../../core/theme/app_theme.dart';

class NextVictoryCard extends StatelessWidget {
  final Map<String, dynamic>? nextVictory;

  const NextVictoryCard({super.key, required this.nextVictory});

  @override
  Widget build(BuildContext context) {
    final data = nextVictory;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    final name = data['name'] as String? ?? '';
    final monthsLeft = (data['monthsLeft'] as int?) ?? 0;

    if (name.isEmpty || monthsLeft <= 0) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final title = isEs ? 'Próxima Victoria 🏆' : 'Next Victory 🏆';
        final body = isEs
            ? '¡Paga $name en $monthsLeft ${monthsLeft == 1 ? 'mes' : 'meses'} a este ritmo!'
            : 'Pay off $name in $monthsLeft ${monthsLeft == 1 ? 'month' : 'months'} at this pace!';
        final subtext = isEs
            ? '¡Sigue adelante — estás más cerca de lo que crees!'
            : 'Keep going — you\'re closer than you think!';

        return Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          padding: const EdgeInsets.all(AppSpacing.mdPlus),
          decoration: BoxDecoration(
            color: AppTheme.accentGood.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: AppTheme.accentGood.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Colors.amber,
                size: 28,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.body,
                        color: AppTheme.accentGood,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: AppTextSize.sm,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Progress bar: fill based on months — use monthsLeft as
                    // inverse indicator (fewer months = more progress shown).
                    // We cap at 36 months for a reasonable visual range.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: LinearProgressIndicator(
                        value: (1.0 - (monthsLeft / 36).clamp(0.0, 1.0)),
                        minHeight: 6,
                        backgroundColor:
                            AppTheme.accentGood.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation(
                          AppTheme.accentGood,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtext,
                      style: TextStyle(
                        fontSize: AppTextSize.xs,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

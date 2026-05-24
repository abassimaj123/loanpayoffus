import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../core/theme/app_theme.dart';

/// Full-screen celebration overlay shown when the user's loan is fully paid off.
///
/// Uses a [ScaleTransition] for a satisfying "pop-in" effect and auto-dismisses
/// after 3 seconds.  A "Share" button lets the user brag about being debt-free.
class MilestoneCelebrationDialog extends StatefulWidget {
  /// Optional share text — pass the debt-free date / savings summary.
  final String? shareText;
  final bool isEs;

  const MilestoneCelebrationDialog({
    super.key,
    this.shareText,
    this.isEs = false,
  });

  /// Show the celebration. Safe to call from [initState] via
  /// [WidgetsBinding.addPostFrameCallback].
  static Future<void> show(
    BuildContext context, {
    String? shareText,
    bool isEs = false,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) =>
          MilestoneCelebrationDialog(shareText: shareText, isEs: isEs),
    );
  }

  @override
  State<MilestoneCelebrationDialog> createState() =>
      _MilestoneCelebrationDialogState();
}

class _MilestoneCelebrationDialogState extends State<MilestoneCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEs = widget.isEs;
    final headline = isEs ? 'Deuda pagada!' : 'Debt Free!';
    final sub = isEs
        ? 'Lo lograste. Sin más pagos.'
        : 'You did it. No more payments.';
    final shareLabel = isEs ? 'Compartir' : 'Share';
    final dismissLabel = isEs ? 'Cerrar' : 'Close';

    return Center(
      child: ScaleTransition(
        scale: _scale,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Celebration emoji
                const Text('\u{1F389}', style: TextStyle(fontSize: 64)),
                const SizedBox(height: AppSpacing.md),
                Text(
                  headline,
                  style: const TextStyle(
                    fontSize: AppTextSize.display,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyMd,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                        ),
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                        child: Text(dismissLabel),
                      ),
                    ),
                    if (widget.shareText != null) ...[
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                          ),
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: Text(shareLabel),
                          onPressed: () {
                            Share.share(
                              widget.shareText!,
                              subject: 'I\'m Debt Free! \u{1F389}',
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

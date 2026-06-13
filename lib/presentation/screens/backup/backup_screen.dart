import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:flutter/material.dart';

import '../../../core/firebase/analytics_service.dart';
import '../../../core/language/language_notifier.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../../main.dart' show debtRefreshNotifier;

/// Backup & restore screen — export all debts + payments to a CSV file, or
/// restore from a previously exported CSV (paste-in, no file-picker dependency).
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _importCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    _importCtrl.dispose();
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppTheme.dangerRed : AppTheme.accentGood,
      ),
    );
  }

  String _errorMessage(AppStrings s, String code) {
    switch (code) {
      case 'empty':
        return s.backupErrEmpty;
      case 'not_backup':
        return s.backupErrNotBackup;
      case 'no_debts':
        return s.backupErrNoDebts;
      case 'bad_debt_columns':
      case 'bad_payment_columns':
        return s.backupErrColumns;
      default:
        return s.backupParseError;
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = isSpanishNotifier.value ? AppStringsES() : AppStringsEN();
    try {
      await BackupService.instance.exportAndShare();
      AnalyticsService.instance.log('backup_exported');
      if (!mounted) return;
      _snack(s.backupExported);
    } catch (_) {
      if (!mounted) return;
      _snack(s.backupParseError, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final s = isSpanishNotifier.value ? AppStringsES() : AppStringsEN();
    final result = BackupService.instance.parse(_importCtrl.text);
    if (!result.isValid) {
      _snack(_errorMessage(s, result.errorCode ?? ''), error: true);
      return;
    }

    final mode = await _confirmRestore(s, result);
    if (mode == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (mode == _RestoreMode.replace) {
        await BackupService.instance.applyReplace(result);
      } else {
        await BackupService.instance.applyMerge(result);
      }
      AnalyticsService.instance.log('backup_imported', {
        'mode': mode.name,
        'debts': result.debts.length,
        'payments': result.payments.length,
      });
      debtRefreshNotifier.value++;
      if (!mounted) return;
      _importCtrl.clear();
      final base = s.backupImported;
      final msg = result.skippedRows > 0
          ? '$base · ${s.backupSkipped.replaceAll('{n}', '${result.skippedRows}')}'
          : base;
      _snack(msg);
    } catch (_) {
      if (!mounted) return;
      _snack(s.backupParseError, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_RestoreMode?> _confirmRestore(
    AppStrings s,
    BackupParseResult result,
  ) {
    final body = s.backupReplaceBody
        .replaceAll('{debts}', '${result.debts.length}')
        .replaceAll('{payments}', '${result.payments.length}');
    return showDialog<_RestoreMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.backupReplaceTitle),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RestoreMode.merge),
            child: Text(s.backupMerge),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _RestoreMode.replace),
            child: Text(s.backupReplace),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

    return Scaffold(
      appBar: AppBar(title: Text(s.backupRestore)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            s.backupSubtitle,
            style: TextStyle(
              fontSize: AppTextSize.body,
              color: Theme.of(context).colorScheme.onSurface.withValues(
                alpha: 0.65,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Export ──
          _ActionCard(
            icon: Icons.ios_share_rounded,
            title: s.exportBackup,
            description: s.exportBackupDesc,
            buttonLabel: s.exportBackup,
            onPressed: _busy ? null : _export,
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Import ──
          Text(
            s.importBackup,
            style: const TextStyle(
              fontSize: AppTextSize.bodyLg,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryDark,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            s.importBackupDesc,
            style: TextStyle(
              fontSize: AppTextSize.sm,
              color: Theme.of(context).colorScheme.onSurface.withValues(
                alpha: 0.6,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _importCtrl,
            maxLines: 8,
            minLines: 4,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: AppTextSize.sm,
            ),
            decoration: InputDecoration(
              hintText: s.backupPasteHint,
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: Text(s.importBackup),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: AppSpacing.lg),
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _RestoreMode { replace, merge }

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppTextSize.bodyLg,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            style: TextStyle(
              fontSize: AppTextSize.sm,
              color: Theme.of(context).colorScheme.onSurface.withValues(
                alpha: 0.6,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(buttonLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

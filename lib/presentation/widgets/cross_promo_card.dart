import 'package:flutter/material.dart';
import '../../core/language/language_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart';
import 'package:calcwise_core/calcwise_core.dart';

// ── Cross-promo: CreditCardAPR ──────────────────────────────────────────────
// Shown to free users only. Dismissible, remembers dismissal for 7 days.
class CrossPromoCard extends StatefulWidget {
  final bool isPremium;
  const CrossPromoCard({super.key, required this.isPremium});

  @override
  State<CrossPromoCard> createState() => _CrossPromoCardState();
}

class _CrossPromoCardState extends State<CrossPromoCard> {
  bool _dismissed = false;
  bool _checked = false;

  static const _prefKey = 'cross_promo_dismissed_loanpayoffus';
  static const _targetName = 'Credit Card APR Calculator';
  static const _targetTagline = 'Crush your credit card debt';
  static const _targetTaglineEs = 'Elimina tu deuda de tarjeta de crédito';

  static const _targetId = 'com.calcwise.creditcardapr';
  static const _accentColor = Color(0xFF4A1FB8);

  @override
  void initState() {
    super.initState();
    _checkDismissed();
  }

  Future<void> _checkDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_prefKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (mounted)
      setState(() {
        _dismissed = age < 7 * 24 * 3600 * 1000;
        _checked = true;
      });
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, DateTime.now().millisecondsSinceEpoch);
    if (mounted) setState(() => _dismissed = true);
  }

  Future<void> _open() async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_targetId',
    );
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || _dismissed || widget.isPremium)
      return const SizedBox.shrink();
    final ct = CalcwiseTheme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 6,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.06),
        border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.mdPlus),
            ),
            child: Icon(
              Icons.credit_card_rounded,
              color: _accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: _accentColor,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: const Text(
                        'CalqWise',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: AppTextSize.xxs,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isSpanishNotifier.value
                          ? 'También de nosotros'
                          : 'Also from us',
                      style: TextStyle(
                        fontSize: AppTextSize.xs,
                        color: ct.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _targetName,
                  style: TextStyle(
                    fontSize: AppTextSize.md,
                    fontWeight: FontWeight.w600,
                    color: ct.textPrimary,
                  ),
                ),
                Text(
                  isSpanishNotifier.value ? _targetTaglineEs : _targetTagline,
                  style: TextStyle(
                    fontSize: AppTextSize.xs,
                    color: ct.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            children: [
              IconButton(
                onPressed: _dismiss,
                tooltip: 'Dismiss',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.close_rounded, size: 16, color: ct.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                onTap: _open,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smPlus,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _accentColor,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    isSpanishNotifier.value ? 'Gratis' : 'Free',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTextSize.xs,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

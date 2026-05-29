import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/language/language_notifier.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../widgets/premium_badge.dart';
import '../../../main.dart' show adService;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.settingsTitle),
        actions: const [PremiumBadge()],
      ),
      bottomNavigationBar: const CalcwiseAdFooter(),
      body: ListView(
        children: [
          // ── Premium ──
          _SectionHeader('Premium'),
          ValueListenableBuilder<bool>(
            valueListenable: freemiumService.hasFullAccessNotifier,
            builder: (context, isPremium, _) => isPremium
                ? ListTile(
                    leading: const Icon(
                      Icons.verified,
                      color: CalcwiseSemanticColors.warnIcon,
                    ),
                    title: Text(s.premiumActive),
                    subtitle: Text(s.premiumSubtitle),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.star_outline,
                          color: AppTheme.primary,
                        ),
                        title: Text(s.getPremium),
                        subtitle: Text(s.premiumSubtitle),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                        onTap: () => IAPService.instance.buy(),
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.restore,
                          color: AppTheme.primary,
                        ),
                        title: Text(s.restorePurchase),
                        onTap: () => IAPService.instance.restore(),
                      ),
                      if (kDebugMode)
                        ListTile(
                          leading: const Icon(
                            Icons.bug_report,
                            color: CalcwiseSemanticColors.warnIcon,
                          ),
                          title: const Text('Force Premium (DEV)'),
                          onTap: () => freemiumService.debugUnlockPremium(),
                        ),
                    ],
                  ),
          ),
          const Divider(),

          // ── Ads ──
          ValueListenableBuilder<bool>(
            valueListenable: freemiumService.isPremiumNotifier,
            builder: (_, isPremium, __) {
              if (isPremium) return const SizedBox.shrink();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SectionHeader(isEs ? 'PUBLICIDAD' : 'ADS'),
                  ValueListenableBuilder<bool>(
                    valueListenable: freemiumService.isRewardedNotifier,
                    builder: (_, isAdFree, __) => ListTile(
                      leading: Icon(
                        isAdFree
                            ? Icons.block_rounded
                            : Icons.play_circle_outline_rounded,
                        color: AppTheme.primary,
                      ),
                      title: Text(isAdFree
                          ? (isEs ? 'Sin anuncios activo' : 'Ad-Free Active')
                          : (isEs ? 'Ver video → 60min sin anuncios' : 'Watch video → 60 min ad-free')),
                      subtitle: isAdFree
                          ? Text(isEs ? 'Disfruta sin interrupciones' : 'Enjoy without interruptions')
                          : null,
                      trailing: isAdFree
                          ? null
                          : Icon(Icons.chevron_right_rounded,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                      onTap: isAdFree
                          ? null
                          : () {
                              Navigator.pop(context);
                              CalcwiseRewardAdSheet.show(context);
                            },
                    ),
                  ),
                  const Divider(),
                ],
              );
            },
          ),

          // ── Language ──
          _SectionHeader(s.language),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'es', label: Text('Español')),
              ],
              selected: {isEs ? 'es' : 'en'},
              onSelectionChanged: (s) =>
                  isSpanishNotifier.value = s.first == 'es',
              style: ButtonStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
              ),
            ),
          ),
          // Theme toggle
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeService.notifier,
            builder: (_, mode, __) => ListTile(
              leading: Icon(themeModeService.icon, color: AppTheme.primary),
              title: Text(themeModeService.label(isSpanish: isEs)),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
              onTap: () => themeModeService.toggle(),
            ),
          ),
          const Divider(),

          // ── Support ──
          _SectionHeader(s.support),
          ListTile(
            leading: const Icon(Icons.email_rounded, color: AppTheme.primary),
            title: Text(s.contactSupport),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            onTap: () => _launch('mailto:support@loanpayoffus.com'),
          ),
          CalcwiseRateAppTile(
            label: isEs ? 'Calificar la app' : 'Rate the App',
          ),
          ListTile(
            leading: const Icon(
              Icons.privacy_tip_rounded,
              color: AppTheme.primary,
            ),
            title: Text(s.privacyPolicy),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            onTap: () => _launch('https://calqwise.com/privacy'),
          ),
          const Divider(),

          // ── Discover ──
          _SectionHeader(s.discover),
          ListTile(
            leading: const Icon(Icons.apps_rounded, color: AppTheme.primary),
            title: const Text('CalqWise'),
            subtitle: Text(s.calcSuite),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            onTap: () => _launch('https://calqwise.com'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Text(
              isEs
                  ? 'Esta aplicación es solo para fines informativos. Consulte a un profesional financiero calificado antes de tomar decisiones financieras.'
                  : 'This app is for informational purposes only. Consult a qualified financial professional before making any financial decisions.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTextSize.xs,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      6,
    ),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: AppTextSize.xs,
        fontWeight: FontWeight.w600,
        color: AppTheme.primary,
        letterSpacing: 0.8,
      ),
    ),
  );
}

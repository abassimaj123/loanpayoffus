import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/language/language_notifier.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../core/review/review_service.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../widgets/premium_badge.dart';

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
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isEs    = isSpanishNotifier.value;
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.settingsTitle),
        actions: const [PremiumBadge()],
      ),
      body: ListView(children: [
        // ── Language ──
        _SectionHeader(s.language),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            const Icon(Icons.language, color: AppTheme.primary),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.language,
                style: const TextStyle(fontSize: 15)),
              Text(isEs ? 'Español' : 'English',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
            ])),
            Switch(
              value: isEs,
              activeColor: AppTheme.primary,
              onChanged: (v) => isSpanishNotifier.value = v,
            ),
            Text(isEs ? 'ES' : 'EN',
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
          ]),
        ),
        // Theme toggle
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeService.notifier,
          builder: (_, mode, __) => ListTile(
            leading: Icon(themeModeService.icon, color: AppTheme.primary),
            title: Text(themeModeService.label(isSpanish: isEs)),
            trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
            onTap: () => themeModeService.toggle(),
          ),
        ),
        const Divider(),

        // ── Premium ──
        _SectionHeader('Premium'),
        ValueListenableBuilder<bool>(
          valueListenable: freemiumService.isPremiumNotifier,
          builder: (context, isPremium, _) => isPremium
            ? ListTile(
                leading: const Icon(Icons.verified, color: Colors.amber),
                title: Text(s.premiumActive),
                subtitle: Text(s.premiumSubtitle),
              )
            : Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  leading: const Icon(Icons.star_outline, color: AppTheme.primary),
                  title: Text(s.getPremium),
                  subtitle: Text(s.premiumSubtitle),
                  trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
                  onTap: () => IAPService.instance.buy(),
                ),
                ListTile(
                  leading: const Icon(Icons.restore, color: AppTheme.primary),
                  title: Text(s.restorePurchase),
                  onTap: () => IAPService.instance.restore(),
                ),
                if (kDebugMode)
                  ListTile(
                    leading: const Icon(Icons.bug_report, color: Colors.orange),
                    title: const Text('Force Premium (DEV)'),
                    onTap: () => freemiumService.debugUnlockPremium(),
                  ),
              ]),
        ),
        const Divider(),

        // ── Support ──
        _SectionHeader(s.support),
        ListTile(
          leading: const Icon(Icons.email_outlined, color: AppTheme.primary),
          title: Text(s.contactSupport),
          trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
          onTap: () => _launch('mailto:support@loanpayoffus.com'),
        ),
        ListTile(
          leading: const Icon(Icons.star_rate_rounded, color: Colors.amber),
          title: Text(s.rateApp),
          trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
          onTap: () => ReviewService.instance.openStoreForReview(),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.primary),
          title: Text(s.privacyPolicy),
          trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
          onTap: () => _launch('https://calqwise.com/privacy'),
        ),
        const Divider(),

        // ── Discover ──
        _SectionHeader(s.discover),
        ListTile(
          leading: const Icon(Icons.apps_outlined, color: AppTheme.primary),
          title: const Text('CalqWise'),
          subtitle: Text(s.calcSuite),
          trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
          onTap: () => _launch('https://calqwise.com'),
        ),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(title.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
        color: AppTheme.primary, letterSpacing: 0.8)),
  );
}

# Release Checklist — Loan Payoff US

## Pre-Build
- [ ] Replace all AdMob placeholder unit IDs (`XXXXXXXXXX`) in `ad_service.dart` with production IDs
- [ ] Confirm `firebase_options.dart` uses production Firebase project config
- [ ] Verify `kReleaseMode` guards are in place for all debug helpers
- [ ] Remove / confirm `debugUnlockPremium()` is unreachable in release builds
- [ ] Bump `version` in `pubspec.yaml` (e.g. `1.0.0+1`)

## Security
- [ ] `android:allowBackup="false"` present in AndroidManifest.xml ✓
- [ ] `network_security_config.xml` referenced in AndroidManifest.xml ✓
- [ ] No hardcoded API keys or secrets in source code
- [ ] ProGuard / R8 rules applied for all obfuscated dependencies

## Android
- [ ] Keystore file available and `key.properties` configured
- [ ] `minSdkVersion` = 21, `targetSdkVersion` = 34+
- [ ] Adaptive icon (`ic_launcher.xml` + `ic_launcher_round.xml`) present ✓
- [ ] Splash screen Android 12+ (`values-v31/styles.xml`, `values-night-v31/styles.xml`) ✓
- [ ] AAB built: `flutter build appbundle --release`
- [ ] AAB passes `bundletool` local device test

## Google Play Store
- [ ] App signed with upload key (not debug key)
- [ ] Store listing EN-US filled in (`store/en-US/listing.txt`) ✓
- [ ] Store listing ES-US filled in (`store/es-US/listing.txt`) ✓
- [ ] Screenshots: phone (min 2), 7-inch tablet optional
- [ ] Feature graphic (1024×500) uploaded
- [ ] Privacy policy URL set → `store/privacy/index.html` hosted ✓
- [ ] Content rating questionnaire completed
- [ ] Target audience: 18+ (financial app)
- [ ] Data safety form filled (local storage, Firebase, AdMob, Play Billing)

## IAP Setup
- [ ] Premium SKU (`premium_onetime`) created in Play Console → Products → In-app products
- [ ] Price set to $2.99 USD with auto-converted regional prices
- [ ] SKU ID matches `IAPService` constant in code
- [ ] Test purchase completed on internal test track

## Freemium / Ads
- [ ] Free tier: 100 saves verified
- [ ] Rewarded ad: 60 min access, max 3x/day (maxRewardedPerDay = 3) ✓
- [ ] Interstitial frequency: every 8 calculations (calcThreshold = 8) ✓
- [ ] AdMob app verified in AdMob console, no policy violations

## Quality Assurance
- [ ] Tested on Android 8, 10, 12, 14 (physical or emulator)
- [ ] Dark mode tested
- [ ] Spanish locale tested (isSpanish toggle)
- [ ] PDF export tested (share_plus + printing)
- [ ] History limit enforced at 100 for free users
- [ ] Premium unlock persists across app restarts
- [ ] Rewarded ad expiry timer works correctly
- [ ] ReviewService triggers after 3rd save ✓
- [ ] Crash-free rate > 99% on Firebase Crashlytics

## Analytics Events to Verify (Firebase)
- [ ] `calculation` event fires with correct params
- [ ] `paywall_shown` fires for hard/soft
- [ ] `paywall_dismissed` fires
- [ ] `rewarded_ad_shown` / `rewarded_ad_earned` fire
- [ ] `rewarded_daily_limit` fires (with try/catch guard) ✓

## Post-Launch
- [ ] Monitor ANR & crash rate in Play Console (first 48h)
- [ ] Monitor Firebase Crashlytics for new crash signatures
- [ ] Reply to first 5 reviews within 24h
- [ ] Schedule 7-day post-launch audit

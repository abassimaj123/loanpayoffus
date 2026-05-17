# 🚀 Batch Automation Scripts

Control all 22+ apps from **one command**. No more running `flutter clean` 22 times.

## Quick Start

```bash
# Check portfolio health (5 min)
bash scripts/stability-check.sh

# Clean all apps (2 min)
bash scripts/batch-clean.sh

# Analyze all apps (5 min)
bash scripts/batch-analyze.sh

# Format all apps (3 min)
bash scripts/batch-format.sh

# Run tests on all apps with tests (10 min)
bash scripts/batch-test.sh
```

---

## Scripts

### 📊 `stability-check.sh`
**Full portfolio health report in one command**

```bash
bash scripts/stability-check.sh
```

Runs:
- `flutter analyze --fatal-infos` on all 22 apps
- `flutter test` on apps with tests
- Shows summary: errors, warnings, test results

Output:
```
✅ PORTFOLIO STABLE — All checks passed!
   Total Errors: 0
   Total Warnings: 5
   Tests Passed: 4
```

**Use before:** Pushing to main, before release, daily check

---

### 🧹 `batch-clean.sh`
**Remove build artifacts and cache from all apps**

```bash
bash scripts/batch-clean.sh
```

Cleans:
- `flutter clean` (removes build/)
- Removes `.dart_tool/` cache
- Frees up disk space (~500MB per app = 10GB total)

**Use:** When builds are broken, to force rebuild, before major changes

---

### 🔍 `batch-analyze.sh`
**Lint all apps and show errors**

```bash
bash scripts/batch-analyze.sh
```

Shows:
- Errors by app
- Warnings by app
- Apps with issues highlighted

Output:
```
❌ AutoLoan: 2 errors, 5 warnings
❌ MortgageUK: 1 error, 3 warnings
✅ MortgageUS: 2 warnings
```

**Use:** Before commit, to catch errors early

---

### 🎨 `batch-format.sh`
**Auto-format all apps**

```bash
bash scripts/batch-format.sh
```

Formats:
- All `.dart` files in `lib/` and `test/`
- Line length: 100 chars
- Follows Dart style guide

Output:
```
✅ Formatted 15 apps
ℹ️  8 apps had formatting changes
```

Then: `git diff` to review, `git add` to stage

**Use:** Before commit, to fix formatting automatically

---

### 🧪 `batch-test.sh`
**Run tests on all apps that have tests**

```bash
bash scripts/batch-test.sh
```

Tests:
- AutoLoan ✅
- MortgageUS ✅
- MortgageUK ✅
- RideProfit ✅

Output:
```
🧪 TEST SUMMARY
Tested: 4 apps
✅ Passed: 4
❌ Failed: 0
```

**Use:** Before merge, to verify tests pass

---

## Common Workflows

### 🔄 Before Committing
```bash
# 1. Clean (remove old builds)
bash scripts/batch-clean.sh

# 2. Format (auto-fix code style)
bash scripts/batch-format.sh

# 3. Analyze (check for errors)
bash scripts/batch-analyze.sh

# 4. Test (run tests)
bash scripts/batch-test.sh

# If all pass:
git add .
git commit -m "..."
git push
```

### 📊 Daily Health Check
```bash
bash scripts/stability-check.sh
```
Shows full portfolio health in one dashboard.

### 🚀 Before Release
```bash
# 1. Full clean
bash scripts/batch-clean.sh

# 2. Analyze all
bash scripts/batch-analyze.sh

# 3. Test all
bash scripts/batch-test.sh

# 4. Final stability check
bash scripts/stability-check.sh

# If all pass → ready to build + release
```

---

## Troubleshooting

### Script fails with "command not found"
Make scripts executable:
```bash
chmod +x scripts/*.sh
```

### Analyze shows errors in one app
```bash
cd <app-name>
flutter analyze --fatal-infos
# Fix errors shown
```

### Tests fail
```bash
cd <app-name>
flutter test --verbose
# Debug test failures
```

### Want to clean specific app?
```bash
cd <app-name>
flutter clean && flutter pub get
```

---

## Performance

| Script | Time | Apps |
|--------|------|------|
| `batch-clean.sh` | 2 min | 15 |
| `batch-analyze.sh` | 5 min | 15 |
| `batch-format.sh` | 3 min | 15 |
| `batch-test.sh` | 10 min | 4 |
| `stability-check.sh` | 20 min | 15 |

Total portfolio check = 20 minutes (vs 2+ hours manual)

---

## Next: Hotfix Automation

See `.github/workflows/hotfix-cascade.yml` for auto-rebuild all apps when calcwise_core changes.

#!/bin/bash

# 🧪 Run tests on all apps with test suites
# Usage: bash scripts/batch-test.sh
# Only runs on apps that have test/ directory

set -e

cd "$(dirname "$0")/.."

echo "🧪 Running tests on all apps..."
echo ""

apps=(
  "AutoLoan"
  "MortgageUS"
  "MortgageUK"
  "RideProfit"
)

tested=0
passed=0
failed=0

for app in "${apps[@]}"; do
  if [ -d "$app" ] && [ -d "$app/test" ]; then
    echo "📦 $app..."
    cd "$app"

    ((tested++))

    if flutter test --coverage 2>&1 | grep -q "passed"; then
      echo "  ✅ Tests PASSED"
      ((passed++))
    else
      echo "  ❌ Tests FAILED"
      ((failed++))
    fi

    cd ..
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 TEST SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Tested: $tested apps"
echo "✅ Passed: $passed"
echo "❌ Failed: $failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$failed" -gt 0 ]; then
  exit 1
else
  exit 0
fi

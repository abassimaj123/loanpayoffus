#!/bin/bash

# 🔍 Analyze all apps with strict linting
# Usage: bash scripts/batch-analyze.sh
# Shows summary of all errors/warnings across portfolio

set -e

cd "$(dirname "$0")/.."

echo "🔍 Analyzing all apps (strict mode)..."
echo ""

apps=(
  "AutoLoan"
  "CreditCardAPR"
  "HELOCApp"
  "JobOfferUS"
  "LoanPayoffUS"
  "MortgageCA"
  "MortgageUK"
  "MortgageUS"
  "PropertyROISuite"
  "RentBuyUS"
  "RentalExpenses"
  "RideProfit"
  "SalaryApp"
  "StudentLoan"
  "TaxeCA"
)

failed_apps=()
error_count=0
warning_count=0

for app in "${apps[@]}"; do
  if [ -d "$app" ]; then
    echo "📦 $app..."
    cd "$app"

    # Run analyze and capture output
    output=$(flutter analyze --no-pub 2>&1 || true)

    # Count errors
    app_errors=$(echo "$output" | grep "error -" | wc -l)
    app_warnings=$(echo "$output" | grep "warning -" | wc -l)

    if [ "$app_errors" -gt 0 ]; then
      echo "  ❌ $app_errors errors, $app_warnings warnings"
      failed_apps+=("$app")
      error_count=$((error_count + app_errors))
      warning_count=$((warning_count + app_warnings))
    else
      echo "  ✅ $app_warnings warnings only"
      warning_count=$((warning_count + app_warnings))
    fi

    cd ..
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 PORTFOLIO ANALYSIS SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total Errors: $error_count"
echo "Total Warnings: $warning_count"
echo ""

if [ ${#failed_apps[@]} -gt 0 ]; then
  echo "❌ Apps with ERRORS:"
  for app in "${failed_apps[@]}"; do
    echo "  - $app"
  done
  echo ""
  echo "Run: cd <app> && flutter analyze --fatal-infos"
  exit 1
else
  echo "✅ ALL APPS PASS (no errors)"
  exit 0
fi

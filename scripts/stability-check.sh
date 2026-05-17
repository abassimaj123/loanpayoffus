#!/bin/bash

# 📊 Full stability check — portfolio health report
# Usage: bash scripts/stability-check.sh
# Shows health of all 22 apps in one dashboard

set -e

cd "$(dirname "$0")/.."

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           📊 PORTFOLIO STABILITY CHECK                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
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

echo "Step 1: Analyzing all apps..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total_errors=0
total_warnings=0
error_apps=()

for app in "${apps[@]}"; do
  if [ -d "$app" ]; then
    cd "$app"
    output=$(flutter analyze --no-pub 2>&1 || true)

    errors=$(echo "$output" | grep "error -" | wc -l)
    warnings=$(echo "$output" | grep "warning -" | wc -l)

    if [ "$errors" -gt 0 ]; then
      echo "❌ $app: $errors errors, $warnings warnings"
      error_apps+=("$app")
      total_errors=$((total_errors + errors))
    else
      echo "✅ $app: $warnings warnings"
    fi

    total_warnings=$((total_warnings + warnings))
    cd ..
  fi
done

echo ""
echo "Step 2: Running tests..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_apps=("AutoLoan" "MortgageUS" "MortgageUK" "RideProfit")
tests_passed=0
tests_failed=0

for app in "${test_apps[@]}"; do
  if [ -d "$app" ] && [ -d "$app/test" ]; then
    cd "$app"
    if flutter test > /dev/null 2>&1; then
      echo "✅ $app: Tests PASSED"
      ((tests_passed++))
    else
      echo "❌ $app: Tests FAILED"
      ((tests_failed++))
    fi
    cd ..
  fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    📊 FINAL REPORT                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "🔍 CODE QUALITY"
echo "   Total Errors:     $total_errors"
echo "   Total Warnings:   $total_warnings"
echo "   Apps with Errors: ${#error_apps[@]}"
echo ""

if [ ${#error_apps[@]} -gt 0 ]; then
  echo "   ❌ Failed apps:"
  for app in "${error_apps[@]}"; do
    echo "      - $app"
  done
  echo ""
fi

echo "🧪 TEST COVERAGE"
echo "   Tests Passed: $tests_passed"
echo "   Tests Failed: $tests_failed"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$total_errors" -eq 0 ] && [ "$tests_failed" -eq 0 ]; then
  echo "✅ PORTFOLIO STABLE — All checks passed!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
else
  echo "❌ PORTFOLIO HAS ISSUES — Fix above before release"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi

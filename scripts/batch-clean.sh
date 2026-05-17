#!/bin/bash

# 🧹 Clean all 22+ apps — removes build artifacts, clears cache
# Usage: bash scripts/batch-clean.sh

set -e

cd "$(dirname "$0")/.."

echo "🧹 Cleaning all apps..."
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

count=0
for app in "${apps[@]}"; do
  if [ -d "$app" ]; then
    echo "📦 $app..."
    cd "$app"

    flutter clean > /dev/null 2>&1 || true
    rm -rf .dart_tool 2>/dev/null || true
    rm -rf build 2>/dev/null || true

    cd ..
    ((count++))
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Cleaned $count apps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

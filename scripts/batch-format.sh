#!/bin/bash

# 🎨 Format all apps with dart format
# Usage: bash scripts/batch-format.sh
# Auto-fixes formatting issues

set -e

cd "$(dirname "$0")/.."

echo "🎨 Formatting all apps..."
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
changed=0

for app in "${apps[@]}"; do
  if [ -d "$app" ]; then
    echo "📦 $app..."
    cd "$app"

    # Format and check if anything changed
    if dart format lib test --line-length 100 > /dev/null 2>&1; then
      ((changed++))
    fi

    ((count++))
    cd ..
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Formatted $count apps"
if [ "$changed" -gt 0 ]; then
  echo "ℹ️  $changed apps had formatting changes"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Tip: git diff to see changes before committing"

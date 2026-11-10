#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# npm_update_outdated.sh
#
# Updates outdated npm packages to their wanted version (respecting the
# version ranges declared in package.json) and saves the result back to
# package.json. Only updates packages where the wanted version has been
# released for more than MIN_AGE_DAYS days (default: 2) to avoid freshly
# released packages that may be unsafe, unstable or get yanked.
#
# After updating packages the script updates browserslist then runs audit fix
#
# Usage:
#   ./npm_update_outdated.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be updated without making any changes
#
# Requirements:
#   node, npm, jq, curl
#
# Files:
#   package.json  (required) - version ranges used to determine wanted version
# -----------------------------------------------------------------------------

PACKAGE_JSON="package.json"
DRY_RUN=false
MIN_AGE_DAYS=5

# Parse --dry-run flag
for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && DRY_RUN=true
done

if [ ! -f "$PACKAGE_JSON" ]; then
  echo "Error: $PACKAGE_JSON not found"
  exit 1
fi

YELLOW='\033[0;33m'
GREEN='\033[0;32m'
GRAY='\033[0;90m'
RESET='\033[0m'

NODE_BIN=$(node -e "process.stdout.write(process.execPath)")
NODE_VER=$(node --version)

echo ""
echo "-----------------------------------------------------------------"
echo "NPM UPDATE SCRIPT"
echo "Date:          $(date +%F)"
echo "Active Node:   $NODE_BIN ($NODE_VER)"
[ "$DRY_RUN" = true ] && echo "Mode:          DRY RUN"
echo "-----------------------------------------------------------------"

echo ""
echo "Checking for outdated packages..."

OUTDATED=$(npm outdated --json 2>/dev/null || true)

if [ -z "$OUTDATED" ] || [ "$OUTDATED" = "{}" ]; then
  echo "All packages are up to date."
  exit 0
fi

COUNT=$(echo "$OUTDATED" | jq 'length')
echo "Found $COUNT outdated package(s)."
echo ""
printf "%-35s %-12s %-12s %-12s %-12s %-8s\n" "PACKAGE" "CURRENT" "WANTED" "LATEST" "RELEASED" "STATUS"
echo "---------------------------------------------------------------------------------------------------------------"

UPDATED=0
SKIPPED=0
TOO_NEW=0

TODAY_EPOCH=$(date +%s)

while IFS= read -r name; do
  row=$(echo "$OUTDATED" | jq -r --arg n "$name" '.[$n]')
  current=$(echo "$row" | jq -r '.current // "-"')
  wanted=$(echo "$row"  | jq -r '.wanted  // "-"')
  latest=$(echo "$row"  | jq -r '.latest  // "-"')

  # Fetch release date for wanted version from npm registry
  rel_date=$(curl -s "https://registry.npmjs.org/$name" | jq -r --arg v "$wanted" '.time[$v] // "unknown"' | cut -c1-10)

  if [ "$rel_date" = "unknown" ]; then
    printf "%-35s %-12s %-12s %-12s %-12s FAILED (no release date)\n" "$name" "$current" "$wanted" "$latest" "unknown"
    continue
  fi

  # Calculate age in days (cross-platform)
  if date -j > /dev/null 2>&1; then
    rel_epoch=$(date -j -f "%Y-%m-%d" "$rel_date" "+%s")
  else
    rel_epoch=$(date -d "$rel_date" "+%s")
  fi
  age_days=$(( (TODAY_EPOCH - rel_epoch) / 86400 ))

  # Skip if wanted == current (nothing to do)
  if [ "$wanted" = "$current" ]; then
    printf "${GRAY}%-35s${RESET} %-12s %-12s %-12s %-12s ${GRAY}UP TO DATE${RESET}\n" "$name" "$current" "$wanted" "$latest" "$rel_date"
    continue
  fi

  # Skip if too new
  if [ "$age_days" -lt "$MIN_AGE_DAYS" ]; then
    printf "${GRAY}%-35s${RESET} %-12s %-12s %-12s %-12s ${GRAY}TOO NEW (%d days old)${RESET}\n" "$name" "$current" "$wanted" "$latest" "$rel_date" "$age_days"
    TOO_NEW=$((TOO_NEW + 1))
    continue
  fi

  # Install updated package
  if [ "$DRY_RUN" = false ]; then
    npm install --save "$name@$wanted" --silent 2>/dev/null
    STATUS=$?
  else
    STATUS=0
  fi

  if [ $STATUS -eq 0 ]; then
    printf "${GREEN}%-35s${RESET} %-12s ${GREEN}%-12s${RESET} %-12s %-12s ${GREEN}UPDATED${RESET}\n" "$name" "$current" "$wanted" "$latest" "$rel_date"
    UPDATED=$((UPDATED + 1))
  else
    printf "%-35s %-12s %-12s %-12s %-12s FAILED\n" "$name" "$current" "$wanted" "$latest" "$rel_date"
  fi

done < <(echo "$OUTDATED" | jq -r 'keys[]')

echo "---------------------------------------------------------------------------------------------------------------"
echo "Updated: $UPDATED  Too new: $TOO_NEW"
echo ""

echo "Updating browserslist"
npx update-browserslist-db@latest

echo "Running audit fix"
npm audit fix  --legacy-peer-deps

echo "Writing npm-dependencies-local.txt"
npm ls --depth=100 > npm-dependencies-local.txt ;
echo "Writing npm-dependencies-global.txt"
npm ls -g --depth=100 > npm-dependencies-global.txt ;
echo "Writing npm-vulnerabilities.txt"
npm audit > npm-vulnerabilities.txt ;

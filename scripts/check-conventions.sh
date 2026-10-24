#!/usr/bin/env bash
# Cheap guard for the rules in AGENTS.md that a compiler cannot enforce. Run from the repo root (CI does).
# Exits non-zero and prints each offending line.
set -u
status=0

# check <description> <grep -E pattern> <path to leave out (a file that is allowed to do it)>
check() {
  local what="$1" pattern="$2" allowed="$3" hits
  hits=$(grep -rnE --include='*.swift' "$pattern" Palabra | grep -v "^$allowed" || true)
  if [ -n "$hits" ]; then
    echo "::error title=Convention::$what"
    echo "$what:"
    echo "$hits"
    status=1
  fi
}

check "Use Motion.animate / Motion.reduced, never withAnimation or .animation(...) directly" 'withAnimation\(|\.animation\([^M]' "Palabra/Core/DesignSystem/Motion.swift"
check "Save through Persistence.save so a failed save is logged and reported, never try? context.save()" 'try\? *[A-Za-z_.]*[cC]ontext\.save\(\)' "Palabra/Core/Storage/Persistence.swift"
check "No hardcoded colours in views: add a role to Theme" 'Color\(hex:' "Palabra/Core/DesignSystem/Theme.swift"
check "No numeric corner radii: use Theme.Radius" 'cornerRadius: *[0-9]' "Palabra/Core/DesignSystem/Theme.swift"

exit $status

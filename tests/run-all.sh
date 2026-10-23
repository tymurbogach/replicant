#!/bin/bash
# Full release gate: static checks, every shell suite, QML, bench budgets,
# phase gates G0-G8, plugin validation and QML lint.
# Suites with their own gate run inside that gate; suites without one run here
# directly, so every suite runs at least once and none runs silently never.
#
# Exit status and summary are explicit: passed, failed, and skipped are counted
# separately. A missing runtime (Omarchy plugin tools, qmltestrunner, real
# desktop session) is a skip, never a silent pass. A run with skips is not an
# unqualified full validation; production readiness still needs F02 and the
# real-runtime evidence in F23.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

passed=0; failed=0; skipped=0
record_pass() { passed=$((passed+1)); }
record_fail() { failed=$((failed+1)); }
record_skip() { skipped=$((skipped+1)); echo "SKIPPED: ${1:-}"; }
run_step() {
  local name="$1"; shift
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  printf '%s\n' "$out"
  if (( rc == 0 )); then
    record_pass
    if grep -qi '^SKIPPED' <<<"$out"; then record_skip; fi
  else
    record_fail
    printf 'FAILED: %s (exit %d)\n' "$name" "$rc" >&2
  fi
  return "$rc"
}
# Steps must not abort the whole run: every suite reports, then the summary
# decides the exit status.
set +e
had_failure=0

section "static: format"
run_step "format" bash "$HERE/test-format.sh" || had_failure=1

section "static: syntax"
syntax_rc=0
for file in "$ROOT"/bin/replicant "$ROOT"/bin/*.sh "$ROOT"/bin/lib/*.sh; do
  bash -n "$file" || syntax_rc=1
done
if (( syntax_rc == 0 )); then record_pass; else record_fail; had_failure=1; fi

section "static: shellcheck (warnings and errors)"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$ROOT"/bin/replicant "$ROOT"/bin/*.sh "$ROOT"/bin/lib/*.sh; then record_pass; else record_fail; had_failure=1; fi
else
  record_skip "shellcheck is not installed — static shell analysis skipped"
fi

section "static: secret scan"
run_step "secret scan" bash "$ROOT/bin/scan-secrets.sh" "$ROOT/bin" "$ROOT/tests" "$ROOT"/*.qml "$ROOT/components" "$ROOT/replicant.js" "$ROOT/docs" "$ROOT/README.md" || had_failure=1

section "static: coverage manifest"
run_step "coverage" bash "$HERE/coverage-check.sh" || had_failure=1

section "static: version bump"
run_step "version" bash "$HERE/check-version-bump.sh" || had_failure=1

section "suites without a phase gate"
for suite in test-cli test-core test-journey test-modules test-interruptions test-usability; do
  echo "--- $suite ---"
  if out=$(bash "$HERE/$suite.sh" 2>&1); then
    printf '%s\n' "$out"
    record_pass
    grep -qi '^SKIPPED' <<<"$out" && record_skip
  else
    printf '%s\n' "$out"
    record_fail; had_failure=1
  fi
done

section "phase gates G0-G8 (run the remaining suites)"
for gate in G0 G1 G2 G3 G4 G5 G6 G7 G8; do
  if out=$(bash "$HERE/gate.sh" "$gate" 2>&1); then
    printf '%s\n' "$out" | tail -n 8
    record_pass
    grep -qi 'skipped' <<<"$out" && record_skip
  else
    printf '%s\n' "$out" | tail -n 20
    record_fail; had_failure=1
  fi
done

section "bench budgets"
run_step "bench-status" bash "$HERE/bench-status.sh" --check || had_failure=1
run_step "bench-settings" bash "$HERE/bench-settings.sh" || had_failure=1

section "plugin"
if command -v omarchy >/dev/null 2>&1; then
  run_step "plugin validate" omarchy plugin validate "$ROOT" || had_failure=1
else
  record_skip "omarchy is not installed — plugin validation skipped (needs a real Omarchy session, see F02/F23)"
fi
if lint_bin=$(command -v qmllint-qt6 || command -v qmllint 2>/dev/null) \
    && [[ -d /usr/share/omarchy/shell ]]; then
  run_step "qmllint" "$lint_bin" -I /usr/share/omarchy/shell "$ROOT"/*.qml "$ROOT"/components/*.qml || had_failure=1
else
  record_skip "Omarchy shell or qmllint is missing — QML lint skipped (needs a real Omarchy session, see F02/F23)"
fi

section "summary"
echo "run-all: $passed passed, $failed failed, $skipped skipped"
if (( had_failure )); then
  echo "run-all FAILED"
  exit 1
fi
if (( skipped > 0 )); then
  echo "run-all passed with skips — not a full validation; real-desktop evidence remains in F02/F23"
  exit 0
fi
echo "All checks passed."

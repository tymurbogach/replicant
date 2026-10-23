#!/bin/bash
# Canonical phase runner for the Replicant v3 plan.
# Usage: ./tests/gate.sh G0|G1|G2|G3|G4|G5|G6|G7|G8
# Every gate runs inside an isolated HOME and XDG environment with local bare
# Git remotes, stubbed externals, and no network access. Each gate asserts
# repository cleanliness and temporary file removal.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
PHASE="${1:-}"

case "$PHASE" in
  G0|G1|G2|G3|G4|G5|G6|G7|G8) ;;
  *) echo "usage: $(basename "$0") G0..G8" >&2; exit 2 ;;
esac

pass=0; fail=0
ok() { printf '  \x1b[32m\xe2\x9c\x93\x1b[0m %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  \x1b[31m\xe2\x9c\x97\x1b[0m %s\n' "$1"; fail=$((fail+1)); }
section() { printf '\n\x1b[1m%s\x1b[0m\n' "$1"; }

# Isolated environment. Every gate gets a fresh HOME, XDG dirs, and a private
# state dir. Nothing in a gate may write to the real user state.
GATE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/replicant-gate-XXXXXX")"
export HOME="$GATE_TMP/home"
export XDG_CONFIG_HOME="$GATE_TMP/config"
export XDG_DATA_HOME="$GATE_TMP/data"
export XDG_STATE_HOME="$GATE_TMP/state"
export XDG_CACHE_HOME="$GATE_TMP/cache"
export OMARCHY_REPLICANT_HOME="$GATE_TMP/replicant"
export GIT_CONFIG_GLOBAL="$GATE_TMP/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$OMARCHY_REPLICANT_HOME"
printf '[user]\n\tname = Gate\n\temail = gate@example.com\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

# Local bare remotes stand in for GitHub. Tests must use these, never the network.
export REPLICANT_GATE_REMOTE="$GATE_TMP/remote.git"
git init --bare -q "$REPLICANT_GATE_REMOTE"

# Reject unexpected network access. Real network tools fail inside gates.
# Suites that need one provide their own fixture first on PATH.
GATE_STUB_DIR="$GATE_TMP/stubbin"
mkdir -p "$GATE_STUB_DIR"
GATE_STUB_LOG="$GATE_STUB_DIR/calls.log"
for tool in curl wget ssh gh; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\necho "gate: network access blocked: %s" >&2\nexit 97\n' "$tool" "$GATE_STUB_LOG" "$tool" > "$GATE_STUB_DIR/$tool"
  chmod +x "$GATE_STUB_DIR/$tool"
done
# Editors, privilege tools, and session tools always fail. A gate that needs
# one writes its own stub and puts it first on PATH.
for tool in sudo pkexec systemctl hyprctl omarchy xdg-open notify-send omarchy-theme-set omarchy-restart-shell omarchy-launch-editor omarchy-launch-floating-terminal-with-presentation vim nvim nano code; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 97\n' "$tool" "$GATE_STUB_LOG" > "$GATE_STUB_DIR/$tool"
  chmod +x "$GATE_STUB_DIR/$tool"
done
export PATH="$GATE_STUB_DIR:$PATH"
export REPLICANT_CATALOG_URL="file:///nonexistent/replicant-gate-catalog.json"
export GIT_PROXY_COMMAND="false"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy || true

cleanup_gate() { rm -rf "$GATE_TMP"; }
trap cleanup_gate EXIT

assert_clean_repo() {
  # A gate must not leave whitespace errors or stray artifacts behind. The
  # plugin checkout is dirty during phase work by design, so this checks the
  # gate's own hygiene, not a clean tree.
  if git -C "$ROOT" diff --check >/dev/null 2>&1; then
    ok "no whitespace errors in the working tree"
  else
    bad "whitespace errors present"; git -C "$ROOT" diff --check >&2 || true
  fi
  if [[ -z "$(git -C "$ROOT" status --porcelain | grep -E '\.log$|\.tmp$|baseline\.txt$' || true)" ]]; then
    ok "no stray test artifacts in the working tree"
  else
    bad "stray test artifacts remain"
    git -C "$ROOT" status --porcelain | grep -E '\.log$|\.tmp$|baseline\.txt$' >&2 || true
  fi
}

assert_no_gate_tmp_left() {
  local left
  left="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'replicant-gate-*' -newer "$GIT_CONFIG_GLOBAL" 2>/dev/null | grep -v "^$GATE_TMP$" || true)"
  if [[ -z "$left" ]]; then
    ok "no stray gate temp dirs left behind"
  else
    bad "stray gate temp dirs remain: $left"
  fi
}

gate_g0() {
  section "G0 isolated environment"
  [[ "$HOME" == "$GATE_TMP/home" ]] && ok "HOME is isolated" || bad "HOME is not isolated"
  [[ "$XDG_STATE_HOME" == "$GATE_TMP/state" ]] && ok "XDG_STATE_HOME is isolated" || bad "XDG_STATE_HOME is not isolated"
  [[ -d "$REPLICANT_GATE_REMOTE" ]] && ok "local bare remote exists" || bad "local bare remote is missing"
  if curl https://example.com >/dev/null 2>&1; then bad "network curl was not blocked"; else ok "network access is rejected"; fi
  if gh auth status >/dev/null 2>&1; then bad "gh stub was not blocking"; else ok "gh is stubbed"; fi
  if sudo true >/dev/null 2>&1; then bad "sudo stub was not blocking"; else ok "privilege tools are stubbed"; fi

  section "G0 benchmark harness"
  [[ -x "$HERE/bench-status.sh" ]] && ok "bench-status.sh is present" || bad "bench-status.sh is missing"
  if "$HERE/bench-status.sh" --help 2>&1 | grep -q -- "--check"; then ok "bench --check mode exists"; else bad "bench --check mode is missing"; fi
  if grep -q 'FULL_BUDGET_MS=250' "$HERE/bench-status.sh" && grep -q 'BRIEF_BUDGET_MS=100' "$HERE/bench-status.sh"; then
    ok "status budgets are 250 ms full and 100 ms brief"
  else
    bad "status budgets are not 250 ms full and 100 ms brief"
  fi
  if grep -q 'XDG_STATE_HOME' "$HERE/bench-status.sh" && ! grep -qE 'HOME/\.local/state' "$HERE/bench-status.sh"; then
    ok "bench never hardcodes user state paths"
  else
    bad "bench still references hardcoded user state"
  fi
  # run-all.sh runs under `set -u`: a skip counter called without a message
  # (the SKIPPED line itself was already printed) must not die on $1. This
  # crashed the CI suites job after G7 in 2026-10-22 (run 39853468945).
  if grep -q 'SKIPPED: ${1:-}' "$HERE/run-all.sh"; then
    ok "run-all skip counter tolerates a missing message"
  else
    bad "run-all skip counter dies on a missing message under set -u"
  fi

  section "G0 command coverage manifest"
  [[ -f "$HERE/coverage.json" ]] && ok "coverage.json exists" || bad "coverage.json is missing"
  if [[ -f "$HERE/coverage.json" ]]; then
    if jq empty "$HERE/coverage.json" >/dev/null 2>&1; then ok "coverage.json is valid JSON"; else bad "coverage.json is not valid JSON"; fi
    missing="$("$HERE/coverage-check.sh" --list-missing 2>/dev/null || true)"
    if [[ -z "$missing" ]]; then
      ok "every public command is mapped to tests"
    else
      bad "unmapped public commands:$missing"
      printf '%s\n' "$missing" >&2
    fi
  fi

  section "G0 QML integration harness"
  [[ -x "$HERE/qml-controller.sh" ]] && ok "qml-controller.sh exists" || bad "qml-controller.sh is missing"
  [[ -f "$HERE/qml/tst_controller.qml" ]] && ok "tst_controller.qml exists" || bad "tst_controller.qml is missing"
  [[ -d "$HERE/qml/mock" ]] && ok "mock Omarchy QML modules exist" || bad "mock Omarchy QML modules are missing"
  if [[ -x "$HERE/qml-controller.sh" ]]; then
    if "$HERE/qml-controller.sh" >/dev/null 2>&1; then ok "QML controller harness passes"; else bad "QML controller harness fails"; fi
  fi

  section "G0 container dependencies"
  for dep in git jq shellcheck diffutils which age; do
    grep -q "$dep" "$HERE/Dockerfile" && ok "Dockerfile lists $dep" || bad "Dockerfile misses $dep"
  done
  grep -q 'qt6-declarative' "$HERE/Dockerfile" && ok "Dockerfile lists qt6-declarative" || bad "Dockerfile misses qt6-declarative"
}

gate_g1() {
  section "G1 schema gate"
  "$HERE/coverage-check.sh" >/dev/null 2>&1 && ok "coverage manifest is complete" || bad "coverage manifest is incomplete"
  if grep -q 'keys == \["format"\] and .format == "replicant"' "$ROOT/bin/lib/schema.sh" 2>/dev/null; then ok "exact schema marker is canonical"; else bad "exact schema marker is missing from schema.sh"; fi
  if grep -q 'validate_entries' "$ROOT/bin/lib/schema.sh" 2>/dev/null; then ok "entries validation exists"; else bad "entries validation is missing from schema.sh"; fi
  if grep -q 'vault/blobs' "$ROOT/bin/lib/schema.sh" 2>/dev/null; then ok "vault layout is required"; else bad "vault layout is not required by schema.sh"; fi
  if [[ ! -f "$ROOT/bin/lib/legacy.sh" && ! -f "$ROOT/bin/lib/migrate.sh" ]]; then ok "no legacy or migration modules remain"; else bad "a legacy or migration module remains"; fi
  if "$HERE/test-schema.sh" >/dev/null 2>&1; then ok "schema suite passes"; else bad "schema suite fails"; fi
}

gate_g2() {
  section "G2 bootstrap gate"
  "$HERE/coverage-check.sh" >/dev/null 2>&1 && ok "coverage manifest is complete" || bad "coverage manifest is incomplete"
  grep -q 'repo_state()' "$ROOT/bin/lib/schema.sh" 2>/dev/null && ok "missing and invalid repos are distinguished" || bad "repo_state is missing from schema.sh"
  grep -q 'bootstrap_fail_at' "$ROOT/bin/lib/repo.sh" 2>/dev/null && ok "failure injection points exist" || bad "bootstrap_fail_at is missing from repo.sh"
  grep -q 'mktemp -d.*replicant-init' "$ROOT/bin/lib/save.sh" 2>/dev/null && ok "init stages in a temp dir" || bad "init has no temp staging"
  grep -q 'mktemp -d.*replicant-clone' "$ROOT/bin/lib/repo.sh" 2>/dev/null && ok "clone stages in a temp dir" || bad "clone has no temp staging"
  if grep -q 'gh repo create "\$name" --private' "$ROOT/bin/lib/repo.sh" 2>/dev/null; then ok "create requests private visibility"; else bad "create does not request --private"; fi
  if grep -qE '^[[:space:]]*(command gh|gh) repo edit' "$ROOT/bin/lib/repo.sh" 2>/dev/null; then bad "bootstrap changes visibility automatically"; else ok "bootstrap never changes visibility automatically"; fi
  grep -q 'gh auth login' "$ROOT/bin/lib/repo.sh" 2>/dev/null && ok "remote failures print recovery commands" || bad "no recovery commands after remote failures"
  if "$HERE/test-bootstrap.sh" >/dev/null 2>&1; then ok "bootstrap suite passes"; else bad "bootstrap suite fails"; fi
}
gate_g3() {
  section "G3 single-format gate"
  "$HERE/coverage-check.sh" >/dev/null 2>&1 && ok "coverage manifest is complete" || bad "coverage manifest is incomplete"
  if [[ -z "$(grep -rnE 'replicant-track|replicant-sync|replicant-profiles|savegame|migrate|legacy|dataVersion|secretFormat|LEGACY_|REMOVED_' "$ROOT/bin/" 2>/dev/null || true)" ]]; then
    ok "bin/ names no retired format"
  else
    bad "bin/ still names a retired format"
  fi
  if [[ -z "$(grep -rnE 'replicant-track|replicant-sync|replicant-profiles|savegame|migrate-v|migrate\.sh|legacy\.sh|legacy_|dataVersion|secretFormat|LEGACY_|REMOVED_' "$ROOT/tests/test-cli.sh" "$ROOT/tests/test-bulk.sh" "$ROOT/tests/test-journey.sh" 2>/dev/null || true)" ]]; then
    ok "core suites name no retired format"
  else
    bad "a core suite still names a retired format"
  fi
}
gate_g4() {
  section "G4 transaction gate"
  "$HERE/coverage-check.sh" >/dev/null 2>&1 && ok "coverage manifest is complete" || bad "coverage manifest is incomplete"
  [[ -f "$ROOT/bin/lib/transaction.sh" ]] && ok "the transaction engine exists" || bad "bin/lib/transaction.sh is missing"
  grep -q 'transaction' "$ROOT/bin/replicant-core.sh" 2>/dev/null && ok "the core loads the transaction engine" || bad "replicant-core.sh does not load transaction.sh"
  grep -q 'core_bulk_transact()' "$ROOT/bin/lib/bulk.sh" 2>/dev/null && ok "bulk runs through the library engine" || bad "core_bulk_transact is missing from bulk.sh"
  if [[ "$(grep -c 'worktree add' "$ROOT/bin/replicant" 2>/dev/null || true)" == 0 ]]; then
    ok "the CLI creates no transaction worktree"
  else
    bad "the CLI still owns worktree transactions"
  fi
  if [[ -z "$(grep -nE 'git[^|]* (add|commit)[^|]*\|\| true' "$ROOT/bin/lib/repo.sh" "$ROOT/bin/lib/transaction.sh" "$ROOT/bin/lib/save.sh" "$ROOT/bin/replicant" 2>/dev/null || true)" ]]; then
    ok "no git add or commit failure is ignored"
  else
    bad "an ignored git add or commit failure remains"
  fi
  grep -q 'core_key_init_transact\|core_key_rotate_transact' "$ROOT/bin/lib/crypto.sh" 2>/dev/null && ok "key writes run through transactions" || bad "key transact wrappers are missing"
  grep -q -- '--force' "$ROOT/bin/replicant" 2>/dev/null && ok "key export knows --force" || bad "key export --force is missing"
  grep -q 'acquire_repo_lock' "$ROOT/bin/replicant" 2>/dev/null && ok "key mutations take the repo lock" || bad "key locking is missing"
  grep -q 'save_plan\|save_stage\|save_validate_commit\|save_activate' "$ROOT/bin/lib/save.sh" 2>/dev/null && ok "core_save is split into phases" || bad "core_save is not split into phases"
  if "$HERE/test-transaction.sh" >/dev/null 2>&1; then ok "transaction suite passes"; else bad "transaction suite fails"; fi
  if "$HERE/test-save.sh" >/dev/null 2>&1; then ok "save suite still passes"; else bad "save suite fails"; fi
  if "$HERE/test-bulk.sh" >/dev/null 2>&1; then ok "bulk suite still passes"; else bad "bulk suite fails"; fi
}
gate_g5() {
  section "G5 status, bulk and settings gate"
  "$HERE/coverage-check.sh" >/dev/null 2>&1 && ok "coverage manifest is complete" || bad "coverage manifest is incomplete"
  grep -Fq 'if [[ "$source" == manifest || "$source" == auto ]]' "$ROOT/bin/lib/status.sh" 2>/dev/null \
    && ok "implicit missing entries are excluded from full status" \
    || bad "full status does not exclude implicit missing entries"
  grep -q 'savedKnown:($r\[19\]|flag)' "$ROOT/bin/lib/status.sh" 2>/dev/null \
    && ok "locked secret persistence is represented as unknown" \
    || bad "savedKnown is missing from the status contract"
  grep -q 'path_unpushed "vault/index.age"' "$ROOT/bin/lib/state.sh" 2>/dev/null \
    && ok "vault index changes reach secret state" \
    || bad "secret state ignores vault index changes"
  grep -q 'gitdirty' "$ROOT/bin/lib/incoming.sh" 2>/dev/null \
    && ok "full and brief unsaved counts include uncommitted copies" \
    || bad "brief count state omits uncommitted copies"
  grep -q '(( count <= 400 ))' "$ROOT/bin/lib/bulk.sh" 2>/dev/null \
    && ok "bulk preserves the 400-file hard limit" \
    || bad "bulk has no 400-file hard limit"
  grep -q 'more than 100 files' "$ROOT/bin/lib/bulk.sh" 2>/dev/null \
    && ok "bulk warns above 100 files" \
    || bad "bulk has no 100-file warning"
  grep -q 'bytes > BULK_LARGE_LIMIT_BYTES' "$ROOT/bin/lib/bulk.sh" 2>/dev/null \
    && ok "bulk measures total directory bytes" \
    || bad "bulk does not measure total directory bytes"
  if grep -Fq 'basename -- "$real"' "$ROOT/bin/lib/bulk.sh" 2>/dev/null && grep -Fq 'TREE_EXCLUDES=(".git"' "$ROOT/bin/lib/tree.sh" 2>/dev/null; then
    ok "tracking .git itself is refused and the copy skips .git inside trees"
  else
    bad "bulk does not refuse .git itself or the copy takes .git inside trees"
  fi
  grep -q 'bulk_require_text_encoding' "$ROOT/bin/lib/bulk.sh" 2>/dev/null \
    && ok "bulk checks content encoding" \
    || bad "bulk does not check content encoding"
  grep -q 'setting_save_id' "$ROOT/bin/lib/settings.sh" 2>/dev/null \
    && grep -q 'cmd_save_setting' "$ROOT/bin/replicant" 2>/dev/null \
    && ok "settings save through their owning entry" \
    || bad "settings still save all entries"
  grep -q 'changed on this machine but was not saved' "$ROOT/bin/replicant" 2>/dev/null \
    && grep -q 'Retry: replicant push' "$ROOT/bin/replicant" 2>/dev/null \
    && ok "settings report persistence and push retries" \
    || bad "settings do not report exact retry commands"
  if "$HERE/test-state.sh" >/dev/null 2>&1; then ok "state parity suite passes"; else bad "state parity suite fails"; fi
  if "$HERE/test-bulk.sh" >/dev/null 2>&1; then ok "bulk validation suite passes"; else bad "bulk validation suite fails"; fi
  if "$HERE/test-bulk-vault.sh" >/dev/null 2>&1; then ok "bulk vault suite passes"; else bad "bulk vault suite fails"; fi
  if "$HERE/test-settings.sh" >/dev/null 2>&1; then ok "settings unit suite passes"; else bad "settings unit suite fails"; fi
  if "$HERE/bench-status-initialized.sh" >/dev/null 2>&1; then ok "initialized status benchmark passes"; else bad "initialized status benchmark fails"; fi
  if "$HERE/test-settings-save.sh" >/dev/null 2>&1; then ok "settings persistence suite passes"; else bad "settings persistence suite fails"; fi
  if "$HERE/test-structured.sh" >/dev/null 2>&1; then ok "structured editors suite passes"; else bad "structured editors suite fails"; fi
  if "$HERE/test-desktop.sh" >/dev/null 2>&1; then ok "desktop editors suite passes"; else bad "desktop editors suite fails"; fi
}
gate_g6() {
  section "G6 secret restore gate"
  "$HERE/coverage-check.sh" >/dev/null 2>&1 && ok "coverage manifest is complete" || bad "coverage manifest is incomplete"
  grep -q 'vault_priv_mktemp' "$ROOT/bin/lib/crypto.sh" 2>/dev/null \
    && ok "privilege is acquired before decrypting outside destinations" \
    || bad "privilege preflight is missing from crypto.sh"
  grep -q 'vault_restore_entry_privileged' "$ROOT/bin/lib/crypto.sh" 2>/dev/null \
    && ok "outside restores stream through a privileged temp" \
    || bad "vault_restore_entry_privileged is missing"
  if grep -n 'vault_restore_entry' "$ROOT/bin/lib/crypto.sh" 2>/dev/null | grep -q 'staged'; then
    bad "restore still stages plaintext below REPLICANT_HOME"
  else
    ok "no plaintext is staged below REPLICANT_HOME"
  fi
  if grep -q '_vault_keep_temp "$plain"' "$ROOT/bin/lib/crypto.sh" 2>/dev/null; then
    bad "restore still retains plaintext for recovery"
  else
    ok "no plaintext is retained for recovery commands"
  fi
  if grep -q '|| mktemp -d' "$ROOT/bin/lib/crypto.sh" 2>/dev/null; then
    bad "a cross-filesystem temp fallback remains"
  else
    ok "no cross-filesystem temp fallback remains"
  fi
  grep -q 'chmod 600' "$ROOT/bin/lib/crypto.sh" 2>/dev/null \
    && ok "mode 0600 is enforced" \
    || bad "mode 0600 is not enforced"
  grep -q 'vault_owner_of\|chown "$owner"' "$ROOT/bin/lib/crypto.sh" 2>/dev/null \
    && ok "the destination owner is preserved" \
    || bad "owner preservation is missing"
  grep -q 'crypto_require_keygen()' "$ROOT/bin/lib/crypto.sh" 2>/dev/null \
    && grep -q 'crypto_require_age || return 1' "$ROOT/bin/lib/crypto.sh" 2>/dev/null \
    && ok "age and age-keygen are verified independently" \
    || bad "age and age-keygen checks are not independent"
  grep -q 'vault:' "$ROOT/bin/lib/restore.sh" 2>/dev/null \
    && grep -q 'never shown' "$ROOT/bin/lib/restore.sh" 2>/dev/null \
    && ok "full restore routes vault secrets without showing contents" \
    || bad "full restore does not handle vault secrets"
  if "$HERE/test-restore-secrets.sh" >/dev/null 2>&1; then ok "restore secrets suite passes"; else bad "restore secrets suite fails"; fi
  if "$HERE/test-crypto.sh" >/dev/null 2>&1; then ok "crypto suite still passes"; else bad "crypto suite fails"; fi
  if "$HERE/test-leaks.sh" >/dev/null 2>&1; then ok "leak scan still passes"; else bad "leak scan fails"; fi
}
gate_g7() {
  section "G7 progress protocol"
  grep -q -- '--progress-json' "$ROOT/bin/replicant" \
    && ok "CLI accepts the global progress option" \
    || bad "CLI has no global progress option"
  grep -q 'progress_stage()' "$ROOT/bin/lib/progress.sh" \
    && grep -q 'progress_result()' "$ROOT/bin/lib/progress.sh" \
    && ok "CLI has stage and result events" \
    || bad "CLI progress helpers are missing"
  grep -q 'progress_stage run false' "$ROOT/bin/replicant" \
    && ok "every command announces its start" \
    || bad "CLI does not announce command start"
  grep -q 'progress_stage commit false' "$ROOT/bin/lib/save.sh" \
    && ok "save disables cancellation before commit" \
    || bad "save does not mark the commit boundary"
  grep -q 'progress_stage commit false' "$ROOT/bin/lib/transaction.sh" \
    && grep -q 'progress_stage publish false' "$ROOT/bin/lib/transaction.sh" \
    && ok "shape transactions stream commit and publish stages" \
    || bad "shape transaction stages are missing"
  grep -q 'progress_stage commit false' "$ROOT/bin/lib/bulk.sh" \
    && ok "bulk streams its commit boundary" \
    || bad "bulk commit stage is missing"
  grep -q 'progress_result local-only' "$ROOT/bin/lib/save.sh" \
    && ok "save reports local-only commits" \
    || bad "save does not distinguish local-only commits"
  [[ -x "$ROOT/bin/replicant-process.sh" ]] \
    && ok "process wrapper forwards cancellation to child processes" \
    || bad "the process-group cancellation wrapper is missing"

  section "G7 controller and parser"
  grep -q 'function dispatchNext(' "$ROOT/ReplicantController.qml" \
    && grep -q 'R.queueEnqueue' "$ROOT/ReplicantController.qml" \
    && ok "the controller owns one priority queue" \
    || bad "controller queue dispatch is missing"
  grep -q 'splitMarker: ""' "$ROOT/ReplicantController.qml" \
    && grep -q 'R.progressParserFeed' "$ROOT/ReplicantController.qml" \
    && ok "the controller parses stderr as a live stream" \
    || bad "controller progress is parsed only after process exit"
  grep -q 'currentMeta.exclusive === true' "$ROOT/Panel.qml" \
    && ! grep -q 'scopeQueue' "$ROOT/Panel.qml" \
    && ok "panel actions use the controller queue" \
    || bad "panel still has a separate action queue or global lock"

  section "G7 navigation lifecycle"
  grep -q 'function openTransient(kind)' "$ROOT/Panel.qml" \
    && grep -q 'function closeTransient()' "$ROOT/Panel.qml" \
    && grep -q 'R.restoreSelection' "$ROOT/Panel.qml" \
    && grep -q 'R.focusIndexFor' "$ROOT/Panel.qml" \
    && ok "panel snapshots restore selection and focus" \
    || bad "panel transient navigation lifecycle is incomplete"
  grep -q 'root.cancelConfirmation()' "$ROOT/Panel.qml" \
    && grep -q 'root.closeTransient()' "$ROOT/Panel.qml" \
    && ok "Escape and cancellation restore the list" \
    || bad "a transient close path skips restoration"

  section "G7 regression suites"
  if "$HERE/test-progress.sh" >/dev/null 2>&1; then ok "progress protocol suite passes"; else bad "progress protocol suite fails"; fi
  if "$HERE/test-g7-navigation.sh" >/dev/null 2>&1; then ok "navigation lifecycle suite passes"; else bad "navigation lifecycle suite fails"; fi
  if "$HERE/qml-controller.sh" >/dev/null 2>&1; then ok "real controller QML suite passes"; else bad "real controller QML suite fails"; fi
  if "$HERE/test-g7-screenshots.sh"; then ok "fixed offscreen screenshots match"; else bad "offscreen screenshot suite fails"; fi
}
gate_g8() {
  section "G8 release gate"
  "$HERE/coverage-check.sh" >/dev/null 2>&1 && ok "coverage manifest is complete" || bad "coverage manifest is incomplete"
  "$HERE/check-version-bump.sh" >/dev/null 2>&1 && ok "plugin version bump is valid" || bad "plugin version bump is missing or invalid"
  [[ "$(jq -r .version "$ROOT/manifest.json" 2>/dev/null)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && ok "plugin manifest carries a release version" || bad "plugin manifest has no release version"
  if [[ -z "$(git -C "$ROOT" status --porcelain | grep -E '\.log$|\.tmp$|baseline\.txt$' || true)" ]]; then
    ok "no stray test artifacts in the working tree"
  else
    bad "stray test artifacts remain"
  fi
  if "$HERE/test-g8.sh" >/dev/null 2>&1; then ok "architecture and documentation suite passes"; else bad "architecture and documentation suite fails"; fi
  if "$HERE/test-reconcile.sh" >/dev/null 2>&1; then ok "reconcile suite passes"; else bad "reconcile suite fails"; fi
  if "$HERE/test-bulk-vault.sh" >/dev/null 2>&1; then ok "bulk vault suite still passes"; else bad "bulk vault suite fails"; fi
  if "$HERE/test-transaction.sh" >/dev/null 2>&1; then ok "transaction suite still passes"; else bad "transaction suite fails"; fi
}

"gate_$(echo "$PHASE" | tr '[:upper:]' '[:lower:]')"

section "gate cleanliness"
assert_clean_repo
assert_no_gate_tmp_left

echo
if (( fail == 0 )); then printf '\x1b[32mGate %s passed (%d checks).\x1b[0m\n' "$PHASE" "$pass"; exit 0
else printf '\x1b[31mGate %s failed: %d of %d checks failed.\x1b[0m\n' "$PHASE" "$fail" "$((pass+fail))"; exit 1; fi

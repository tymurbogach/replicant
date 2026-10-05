# shellcheck shell=bash disable=SC2034
# discover.sh: entries found rather than listed: plugin configs and Hyprland modules.
# Sourced by replicant-core.sh, which sets the paths it uses. It defines
# functions and data and runs nothing. Other modules read its data.

# discover_plugin_entries — auto-detects configs of OTHER installed Omarchy plugins
# (goal: any-monitor, sleepwalker, enter-the-matrix, future dev/omarchy-*, and
# third-party plugins too). Convention observed on this system: each plugin <id>
# keeps its user config at ~/.config/omarchy/<last-segment-of-id>.json (e.g.
# any-monitor.json, enter-the-matrix.json). No need to touch MANIFEST when a new
# plugin following that convention is installed.
# Emits one "src<TAB>rel<TAB>label" line per detected plugin with a config present.
discover_plugin_entries() {
  local plugins_dir="$HOME/.config/omarchy/plugins"
  [[ -d "$plugins_dir" ]] || return 0
  local -a mfs=()
  local mf pid pname short altShort cand src rel
  for mf in "$plugins_dir"/*/manifest.json; do [[ -f "$mf" ]] && mfs+=("$mf"); done
  (( ${#mfs[@]} )) || return 0
  # One jq for every manifest. This runs each time the core is loaded, which
  # includes the bar's once-a-minute poll, and a process per plugin added up.
  while IFS=$'\t' read -r pid pname; do
    [[ -n "$pid" ]] || continue
    [[ "$pid" == "io.github.tymurbogach.replicant" ]] && continue
    short="${pid##*.}"
    altShort="${short#omarchy-}"
    local -a cands=(
      "$HOME/.config/omarchy/$short.json"
      "$HOME/.config/$short/config.json"
      "$HOME/.config/$short/settings.json"
      "$HOME/.config/$short.json"
      "$HOME/.config/$pid/config.json"
      "$HOME/.config/$pid/settings.json"
      "$HOME/.config/$pid.json"
    )
    if [[ "$short" == omarchy-* ]]; then
      cands+=(
        "$HOME/.config/$altShort/config.json"
        "$HOME/.config/$altShort/settings.json"
        "$HOME/.config/$altShort.json"
      )
    fi
    for cand in "${cands[@]}"; do
      if [[ -f "$cand" ]]; then
        if [[ "$cand" == "$HOME/.config/omarchy/$short.json" ]]; then
          rel="plugins/$short.json"
        else
          rel="${cand#"$HOME/.config/"}"
        fi
        printf '%s\t%s\t%s\n' "$cand" "$rel" "$pname"
        break
      fi
    done
  done < <(jq -r '[.id // "", .name // .id // ""] | @tsv' "${mfs[@]}" 2>/dev/null)
}

# discover_kept_plugin_configs — plugin configs the repo holds for a plugin this
# machine does not have, but some machine that writes this repo does.
#
# Discovery used to be only what is installed HERE. The prune pass removes
# whatever is not tracked, so a laptop without a plugin deleted the desktop's
# settings for it on every save, and the desktop put them back on its next one.
# That is the "older machine deletes what a newer one tracks" bug, one level
# down. Which plugins exist on the other machine is a question for its
# inventory, state/<machine>/omarchy-plugins.txt, not for this machine's
# plugins directory.
#
# When no inventory records the plugin any more, the config is not kept and
# the next save prunes it. git still has it.
discover_kept_plugin_configs() {
  local -A recorded=()
  local short id f root
  while IFS=$'\t' read -r short id; do
    [[ -n "$short" ]] && recorded["$short"]="$id"
  done < <(awk -F'\t' '!/^#/ && $1 != "" { n = split($1, a, "."); print a[n] "\t" $1 }' \
             "$STATE_ROOT"/*/omarchy-plugins.txt 2>/dev/null)
  (( ${#recorded[@]} )) || return 0
  local -a roots=("$CONFIG_DIR/plugins")
  [[ -d "$REPO_DIR/profiles" ]] && roots+=("$REPO_DIR/profiles/$(current_profile)/config/plugins")
  for root in "${roots[@]}"; do
    for f in "$root"/*.json; do
      [[ -f "$f" ]] || continue
      short="${f##*/}"; short="${short%.json}"
      id="${recorded[$short]:-}"
      [[ -n "$id" && "$id" != "io.github.tymurbogach.replicant" ]] || continue
      printf '%s\t%s\t%s\n' "$HOME/.config/omarchy/$short.json" "plugins/$short.json" "$id"
    done
  done
}

# ─── The Hyprland modules hyprland.lua loads ────────────────────────────────
# MANIFEST names the five modules Omarchy's own hyprland.lua loads. It cannot
# name the others: OmaSettings appends `require("hypr.omasettings")` and writes
# everything its window sets into ~/.config/hypr/omasettings.lua, and people
# split their own config into modules the same way. The repo then held a
# hyprland.lua loading a file the repo did not have. Restored on another
# machine, that is a Hyprland config error, and every setting in the module is
# gone.
#
# "What does my Hyprland config consist of" is answered by the config: every
# require of a `hypr.` module, followed through the modules it loads, in both
# the live file and the repo's copy. The repo's copy counts because a machine
# restoring for the first time has Omarchy's stock hyprland.lua, which loads
# nothing of the user's.

# lua_hypr_requires <file> — one `hypr.` module name per line. Comments are
# stripped first: a require that is commented out is not a load.
lua_hypr_requires() {
  sed -e 's/--.*$//' -- "$1" 2>/dev/null |
    grep -oE "require[[:space:]]*\(?[[:space:]]*[\"']hypr\.[A-Za-z0-9_.-]+[\"']" |
    sed -E "s/.*[\"']hypr\.([A-Za-z0-9_.-]+)[\"'].*/\1/" |
    grep -vE '(^\.|\.$|\.\.)' || true
}

# hypr_module_rel <module> — its tracked id, as Lua's path would find it on this
# machine or in the repo: hypr/<a/b>.lua, else hypr/<a/b>/init.lua.
hypr_module_rel() {
  local base="hypr/${1//.//}" cand
  for cand in "$base.lua" "$base/init.lua"; do
    [[ -f "$HOME/.config/$cand" || -f "$(repo_path_for "$cand")" ]] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}

discover_hypr_modules() {
  local -a queue=("hypr/hyprland.lua")
  local -A seen=(["hypr/hyprland.lua"]=1)
  local rel f mod mrel
  while (( ${#queue[@]} )); do
    rel="${queue[0]}"; queue=("${queue[@]:1}")
    for f in "$HOME/.config/$rel" "$(repo_path_for "$rel")"; do
      [[ -f "$f" ]] || continue
      while IFS= read -r mod; do
        [[ -n "$mod" ]] || continue
        mrel=$(hypr_module_rel "$mod") || continue
        [[ -n "${seen[$mrel]:-}" ]] && continue
        seen["$mrel"]=1; queue+=("$mrel")
        printf '%s\t%s\t%s\n' "$HOME/.config/$mrel" "$mrel" "$mrel"
      done < <(lua_hypr_requires "$f")
    done
  done
}

# unresolved_hypr_modules — `hypr.` modules the LIVE config loads that exist
# nowhere on this machine. Hyprland reports each one as an error on every
# reload, and a module nobody has cannot be backed up.
unresolved_hypr_modules() {
  local f mod
  for f in "$HOME/.config/hypr/hyprland.lua" "$HOME"/.config/hypr/*.lua; do
    [[ -f "$f" ]] || continue
    while IFS= read -r mod; do
      [[ -f "$HOME/.config/hypr/${mod//.//}.lua" || -f "$HOME/.config/hypr/${mod//.//}/init.lua" ]] && continue
      printf 'hypr.%s\n' "$mod"
    done < <(lua_hypr_requires "$f")
  done | sort -u
}

is_auto_entry() { [[ -n "${AUTO_LABEL[$1]+x}" ]]; }

# load_auto_manifest — fill AUTO_MANIFEST and fold it into TRACKED. An entry a
# person already listed wins: a path they track by hand, or one inside a
# directory they track, is theirs and is not found a second time.
load_auto_manifest() {
  local src rel label entry taken
  AUTO_MANIFEST=(); AUTO_LABEL=()
  rebuild_tracked
  while IFS=$'\t' read -r src rel label; do
    [[ -n "$rel" ]] || continue
    is_auto_entry "$rel" && continue
    is_tracked_path "$src" && continue
    taken=0
    for entry in "${TRACKED[@]}"; do [[ "${entry##*:}" == "$rel" ]] && { taken=1; break; }; done
    (( taken )) && continue
    AUTO_MANIFEST+=("$src:$rel"); AUTO_LABEL["$rel"]="$label"
  done < <(discover_plugin_entries; discover_kept_plugin_configs; discover_hypr_modules)
  rebuild_tracked
}

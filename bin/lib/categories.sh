# shellcheck shell=bash disable=SC2034
# categories.sh: the areas that the panel files every entry under.
# Sourced by replicant-core.sh, which sets the paths it uses. It defines
# functions and data and runs nothing. Other modules read its data.

# ─── CATEGORIES — how the panel files everything, and how each is put back ───
# The panel shows one collapsed card per category instead of one long list of
# 40 files, so nothing needs a long scroll. `method` is the honest answer to
# "what will Replicant actually run to restore this?" — it is shown in the UI
# rather than hidden in the code, because using the Omarchy-sanctioned path
# (omarchy theme set, omarchy plugin add, hyprctl reload) instead of blindly
# copying files back is the whole point of this plugin.
#
# Format: "id|icon|label|description|method"
CATEGORIES=(
  "shortcuts|󰌌|Shortcuts|Your keybinding overrides, on top of Omarchy's defaults|Copied back, then hyprctl reload"
  "appearance|󰏘|Appearance|Theme, look & feel, fonts, interface density and branding|Theme re-applied with omarchy theme set"
  "desktop|󰍹|Desktop & bar|The Omarchy shell: bar layout, widgets, menu and idle|Written to shell.json / shell.toml, which the shell watches live"
  "hyprland|󰖯|Hyprland|Input, monitors, autostart, lock screen and night light|Copied back, then hyprctl reload and a config-error check"
  "terminal|󰆍|Terminal & shell|Alacritty, foot, tmux, bashrc and which terminal opens|Copied back, then omarchy restart terminal"
  "development|󰅴|Development|git, editors, Claude and opencode, mise, VS Code|Copied back; nothing needs restarting"
  "secrets|󰌆|Secrets & keys|SSH keys, tokens and .env files — private, mode 600|Copied back as mode 600; contents are never printed"
  "plugins|󰐱|Plugins|Every installed plugin, and where its settings live|Plugin settings copied back; third-party plugins are installed only on request"
  "scripts|󰈙|Scripts|Your helper scripts under ~/.local/bin and Omarchy hooks|Copied back with the executable bit kept"
  "system|󰋊|System|systemd drop-ins for lid and sleep|Needs root: one file asks for it, a full restore prints sudo"
  "other|󰈔|Other|Anything else you asked Replicant to track|Copied back as-is"
)
CATEGORY_ORDER=(shortcuts appearance desktop hyprland terminal development secrets plugins scripts system other)

# `fields`, not `f`. Bash scopes dynamically, so a local named `f` here is
# visible inside anything this calls — and `f` means "the file being examined"
# in three other functions in this file. That collision is what made
# suggest_skip_reason work by accident for four releases.
category_field() { local -a fields; IFS='|' read -ra fields <<<"$1"; printf '%s' "${fields[$(($2 - 1))]:-}"; }
find_category() {
  local id="$1" entry
  # A prefix match, as in find_setting: no fork per line.
  for entry in "${CATEGORIES[@]}"; do
    [[ "${entry%%|*}" == "$id" ]] && { printf '%s\n' "$entry"; return 0; }
  done
  return 1
}

is_plugin_config_rel() {
  local rel="$1" prefix
  prefix="${rel%%/*}"
  [[ -z "$prefix" || "$prefix" == "$rel" ]] && prefix="${rel%%.*}"
  if [[ -z "${PLUGIN_PREFIXES_LOADED:-}" ]]; then
    PLUGIN_PREFIXES_LOADED=1
    declare -gA PLUGIN_PREFIXES=()
    local mf pid short
    for mf in "$HOME/.config/omarchy/plugins"/*/manifest.json; do
      [[ -f "$mf" ]] || continue
      pid=$(jq -r '.id // empty' "$mf" 2>/dev/null) || continue
      [[ -n "$pid" ]] || continue
      PLUGIN_PREFIXES["$pid"]=1
      short="${pid##*.}"
      PLUGIN_PREFIXES["$short"]=1
      [[ "$short" == omarchy-* ]] && PLUGIN_PREFIXES["${short#omarchy-}"]=1
    done
    if [[ -d "${STATE_ROOT:-}" ]]; then
      while IFS=$'\t' read -r pid _rest; do
        [[ -n "$pid" && "$pid" != \#* ]] || continue
        PLUGIN_PREFIXES["$pid"]=1
        short="${pid##*.}"
        PLUGIN_PREFIXES["$short"]=1
        [[ "$short" == omarchy-* ]] && PLUGIN_PREFIXES["${short#omarchy-}"]=1
      done < <(cat "$STATE_ROOT"/*/omarchy-plugins.txt 2>/dev/null)
    fi
  fi
  [[ -n "${PLUGIN_PREFIXES[$prefix]:-}" ]]
}

# category_for_rel <repo-relative-id> — one place deciding where a tracked file
# shows up. It used to live inline in build_configs_json, which meant the CLI
# and the panel could disagree about what "appearance" meant.
category_for_rel() {
  case "$1" in
    hypr/bindings.lua)                                 echo shortcuts ;;
    hypr/looknfeel.lua|omarchy/theme.name|omarchy/shell.toml|branding/*|fontconfig/*|omarchy/themed/*) echo appearance ;;
    omarchy/shell.json|omarchy/extensions/*)           echo desktop ;;
    hypr/*)                                            echo hyprland ;;
    alacritty/*|foot/*|kitty/*|ghostty/*|xdg-terminals.list|home/*) echo terminal ;;
    # nvim/ is not listed separately: `nvim/*` already matches it, since * matches
    # the empty string. Having both said the author was unsure which one worked.
    git/*|vscode/*|mise/*|claude/*|opencode/*|dev/*|nvim/*|omarchy/defaults/*) echo development ;;
    ssh/*|env/*)                                       echo secrets ;;
    plugins/*)                                         echo plugins ;;
    bin/*|omarchy/hooks/*|omarchy-audit-ignore)        echo scripts ;;
    etc/*|uwsm/*|systemd/*)                            echo system ;;
    mimeapps.list)                                     echo desktop ;;
    starship.toml|btop/*|lazygit/*|tmux/*|herdr/*)     echo terminal ;;
    *)
      if is_plugin_config_rel "$1"; then
        echo plugins
      else
        echo other
      fi
      ;;
  esac
}

build_categories_json() {
  local entries=() entry
  local id
  for id in "${CATEGORY_ORDER[@]}"; do
    entry=$(find_category "$id") || continue
    entries+=("$(jq -nc --arg id "$id" \
      --arg icon "$(category_field "$entry" 2)" \
      --arg label "$(category_field "$entry" 3)" \
      --arg description "$(category_field "$entry" 4)" \
      --arg method "$(category_field "$entry" 5)" \
      '{id:$id,icon:$icon,label:$label,description:$description,method:$method}')")
  done
  printf '%s\n' "${entries[@]}" | jq -s '.'
}

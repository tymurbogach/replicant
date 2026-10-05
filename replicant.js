.pragma library
// Pure functions that the bar, the panel and its components share. No QML
// context reaches a library file, so every input is a parameter. That is what
// lets tests/qml/tst_replicant.qml test them without a running shell.

// Icons are held as Material Design Icon CODE POINTS, never as pasted glyphs.
// Every one of them lives above U+FFFF, where a re-encoding of a file silently
// truncates the character into a different symbol. The name of each icon is in
// a comment beside its code point.
function mdi(cp) { return String.fromCodePoint(cp) }

// "1 file", "4 files". The panel printed "file(s)" eleven times on one screen,
// and the number was always right there next to it.
function plural(n, one, many) {
  var count = Number(n) || 0
  return n + " " + (count === 1 ? one : (many || one + "s"))
}

// ── sync states ─────────────────────────────────────────────────────────────
// One place maps a sync state to how it looks, so a new state cannot be added
// to the core and silently render as the fallback in three different rows.
function stateGlyph(st) {
  if (st === "off") return "⊘"
  if (st === "missing") return "·"
  // Down, against unsaved's dot and unpushed's up arrow. The three states that
  // ask for an action say which direction that action moves the file in.
  if (st === "incoming") return "↓"
  if (st === "unsaved") return "●"
  if (st === "unpushed") return "↑"
  if (st === "default") return "○"
  // Locked out: the secret is here and so is its vault copy, but without the
  // key no one can say whether they match. A warning sign, below U+FFFF like
  // every other badge, so the legend can print it literally.
  if (st === "locked") return "⚠"
  // Not a state of the core: a scope change the panel has sent and the next
  // status has not confirmed yet.
  if (st === "pending") return "…"
  if (st === "saved") return "✓"
  return "◆"
}

// The colour role of a state. The panel maps each role to its own palette.
// "incoming" has a role of its own, and deliberately not the accent that the
// other two "do something" states share: pressing Save on an incoming row is
// the one mistake in this panel that destroys somebody else's work, so its
// badge must not look like the badge that asks for Save.
function stateRole(st) {
  if (st === "incoming") return "warn"
  // Locked asks for a different action (import the key), not for Save, so it
  // shares incoming's warning colour and never Save's accent.
  if (st === "locked") return "warn"
  if (st === "unsaved" || st === "unpushed") return "accent"
  if (st === "saved") return "ok"
  if (st !== "off" && st !== "missing" && st !== "default" && st !== "pending") return "warn"
  return "dim"
}

// The transport state is separate from a file state. It tells the panel which
// remote action is available without changing the per-file compatibility field.
function remoteStateWord(st) {
  if (st === "local-only") return "No remote"
  if (st === "remote-missing") return "GitHub repository is missing"
  if (st === "offline") return "Remote offline"
  if (st === "ahead") return "Local commits not pushed"
  if (st === "behind") return "Remote commits pending"
  if (st === "diverged") return "Branches diverged"
  if (st === "synced") return "Remote synced"
  return "Remote status unknown"
}

function remoteStateRole(st) {
  if (st === "offline" || st === "remote-missing" || st === "behind" || st === "diverged") return "warn"
  if (st === "ahead") return "accent"
  if (st === "synced") return "ok"
  return "dim"
}

// A status failure is not an empty status. The caller must only replace its
// last known state when the CLI succeeds and returns the status contract.
function statusResponse(text, code) {
  if (Number(code) !== 0) {
    return {
      ok: false,
      title: "Could not read Replicant status",
      error: "The Replicant CLI failed with exit " + Number(code) + ". Check the plugin installation, then retry."
    }
  }
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || (parsed.initialized !== true && parsed.initialized !== false)) throw new Error("missing initialized")
    return { ok: true, repoState: parsed, title: "", error: "" }
  } catch (e) {
    return {
      ok: false,
      title: "Invalid Replicant status",
      error: "The Replicant CLI returned invalid status data. Retry the request."
    }
  }
}

function stateWord(st) {
  // "off", the word the scope button, the legend and the card already use.
  // This said "not synced": two words for one state, two tabs apart.
  if (st === "off") return "switched off"
  if (st === "missing") return "not on this machine"
  // Short on purpose. These are printed beside the path on a row that also
  // carries a Save button and sits under a banner that already says "press
  // Save to GitHub", so a longer sentence bought nothing and cost the path its
  // last few characters on exactly the rows that had one worth reading.
  if (st === "incoming") return "newer copy in your repo"
  if (st === "unsaved") return "not saved yet"
  if (st === "unpushed") return "not pushed yet"
  if (st === "default") return "untouched Omarchy default"
  if (st === "locked") return "locked, needs key"
  if (st === "pending") return "saving the change…"
  if (st === "saved") return "saved on GitHub"
  return "unknown state"
}

// ── the header ──────────────────────────────────────────────────────────────
// f: { asked, ready, ahead, behind, incoming, dirty }. The counts come from the
// rows themselves, so the header and the badges answer to one source.
function summary(f) {
  var facts = f || {}
  if (!facts.asked) return "checking…"
  if (!facts.ready) return "not set up yet"
  if (facts.ahead > 0 && facts.behind > 0) return "diverged"
  if (facts.behind > 0) return facts.behind + " waiting on GitHub"
  if (facts.incoming > 0) return "changes to restore"
  if (facts.dirty > 0 || facts.ahead > 0) return "unsaved changes"
  return "everything saved"
}

// One sentence telling the user what to do next, or nothing at all when there
// is nothing to do. A banner that is always present stops being read.
function advice(f) {
  var facts = f || {}
  if (!facts.asked || !facts.ready) return ""
  if (facts.behind > 0) return "Another machine saved " + plural(facts.behind, "change") + " — press Pull to bring them here."
  // Before the unsaved line, and that order is the whole point of the state.
  // Both mean "this file and its copy differ"; only this one knows which way,
  // and pressing Save here commits over what the other machine saved.
  // One line, and it has to fit on one line: the banner elides, and the half
  // that got cut was the half naming the button.
  if (facts.incoming > 0) return plural(facts.incoming, "file") + " came from another machine — press Restore, not Save."
  if (facts.dirty > 0) return plural(facts.dirty, "file") + " changed on this machine — press Save to GitHub."
  if (facts.ahead > 0) return plural(facts.ahead, "commit") + " committed but not pushed — press Save to GitHub."
  return ""
}

// The status card on the Overview tab: one headline, one line under it, and a
// tone. f is the facts of summary() plus { tracked, lastSave } (lastSave is
// the agoText of the newest save, or "").
function headline(f) {
  var facts = f || {}
  if (!facts.asked) return { title: "Checking this machine…", detail: "", tone: "dim" }
  if (!facts.ready) return { title: "No backup repo yet", detail: "", tone: "dim" }
  if (facts.ahead > 0 && facts.behind > 0)
    return { title: "This machine and GitHub have diverged", detail: "Pull first, then save.", tone: "warn" }
  if (facts.behind > 0)
    return { title: plural(facts.behind, "change") + " waiting on GitHub",
             detail: "Another machine saved. Pull brings the changes here.", tone: "warn" }
  if (facts.incoming > 0)
    return { title: plural(facts.incoming, "file") + " came from another machine",
             detail: "Restore puts " + (facts.incoming === 1 ? "it" : "them") + " here. Save would overwrite that work.", tone: "warn" }
  if (facts.dirty > 0)
    return { title: plural(facts.dirty, "file") + " not saved yet",
             detail: "Save copies, commits and pushes them.", tone: "accent" }
  if (facts.ahead > 0)
    return { title: plural(facts.ahead, "commit") + " not pushed yet",
             detail: "Save to GitHub pushes them.", tone: "accent" }
  return { title: "Everything is saved",
           detail: plural(facts.tracked || 0, "file") + " backed up" + (facts.lastSave ? " · last save " + facts.lastSave : ""),
           tone: "ok" }
}

// A list of names for a tooltip: the first few, and how many more there are.
function nameList(names, max) {
  var list = names || []
  var m = max || 8
  if (!(m > 0)) m = 8
  var out = list.slice(0, m).map(function(n) { return "  " + n })
  if (list.length > m) out.push("  +" + (list.length - m) + " more")
  return out.join("\n")
}

// A repo path in the words of the Configs tab. config/x is x, a profile's copy
// says whose it is, and a secret says that it is one.
function repoPathLabel(p) {
  var s = String(p || "")
  var m = s.match(/^profiles\/([^\/]+)\/config\/(.+)$/)
  if (m) return { label: m[2], note: m[1] + " profile" }
  if (s.indexOf("config/") === 0) return { label: s.slice(7), note: "" }
  if (s.indexOf("secrets/") === 0) return { label: s.slice(8), note: "secret" }
  return { label: s, note: "" }
}

// Where the repo keeps a row's copy. repo_path_for is the rule in the core;
// this only says it in words, next to the row.
function repoCopyText(row, scope, profile) {
  var r = row || {}
  if (!r.id) return ""
  if (r.secret) return "secrets/" + r.id
  if (scope === "profile") {
    var who = String(profile || "").trim()
    if (who === "") return "config/" + r.id
    return "profiles/" + who + "/config/" + r.id
  }
  return "config/" + r.id
}

// Bytes, the way `ls -h` says them.
function sizeText(b) {
  var n = Number(b) || 0
  if (!(n > 0)) return "0 B"
  if (n < 1024) return Math.floor(n) + " B"
  if (n < 1048576) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB"
  if (n < 1073741824) return (n / 1048576).toFixed(1) + " MB"
  if (n < 1099511627776) return (n / 1073741824).toFixed(1) + " GB"
  return (n / 1099511627776).toFixed(1) + " TB"
}

// A path the way the CLI prints it: under $HOME it starts with ~.
function prettyPath(p, home) {
  var s = String(p || "")
  if (home && (s === home || s.indexOf(home + "/") === 0)) return "~" + s.slice(home.length)
  return s
}

// The page of a GitHub remote, for "Open on GitHub". Anything else has none.
function webUrl(remote) {
  var r = String(remote || "")
  var m = r.match(/^git@github\.com:(.+?)(\.git)?$/)
  if (m) return "https://github.com/" + m[1]
  m = r.match(/^https:\/\/github\.com\/(.+?)(\.git)?$/)
  if (m) return "https://github.com/" + m[1]
  return ""
}

// The row states that have a button worth pressing. A file gone from this
// machine is one: it asks whether to bring it back or to forget it.
function needsAttention(st) {
  return st === "unsaved" || st === "unpushed" || st === "incoming" || st === "missing" || st === "locked"
}

// Which rows a filter keeps: "all", "changed" or "off".
function rowMatchesFilter(row, filter) {
  if (filter === "changed") return needsAttention(row.sync_state)
  if (filter === "incoming") return row.sync_state === "incoming"
  if (filter === "missing") return row.sync_state === "missing"
  if (filter === "locked") return row.sync_state === "locked" || row.locked === true
  if (filter === "large") return Number(row.size || 0) >= 1024 * 1024
  if (filter === "off") return row.sync_state === "off"
  return true
}

// Whether a restore would write this row: it is synced, the repo holds a copy,
// and the copy differs from what is here, or nothing is here.
function wouldRestore(row) {
  if (row.synced === false || row.saved !== true) return false
  return row.sync_state === "unsaved" || row.sync_state === "incoming" || row.sync_state === "missing"
}

// The scope a row shows. A change the user just made wins until a status that
// was built after the change arrives.
function effectiveScope(row, overrides) {
  var o = overrides ? overrides[row.id] : undefined
  return o ? o : (row.scope || "shared")
}

// The state a row shows while its scope change is in flight. Switched off is
// known at once. Any other scope change moves the copy, so it says pending
// until a status built after the change confirms the new location.
function displayState(row, overrides) {
  var o = overrides ? overrides[row.id] : undefined
  if (!o || o === (row.scope || "shared")) return row.sync_state
  if (o === "off") return "off"
  return "pending"
}

// Project every row through the optimistic scope state once. All panel views
// consume this list, so a pending change cannot leave stale derived data.
function effectiveRows(repoState, overrides) {
  return allRows(repoState).map(function(row) {
    var projected = {}
    for (var key in row) projected[key] = row[key]
    projected.scope = effectiveScope(row, overrides)
    projected.sync_state = displayState(row, overrides)
    projected.synced = projected.scope !== "off"
    return projected
  })
}

// The visible order is global. Cards do not create separate selection ranges.
function visibleRows(repoState, categoryCards, suggestions, search, filter) {
  var out = []
  var cards = categoryCards || []
  for (var i = 0; i < cards.length; i++) {
    var rows = cards[i].rows || []
    for (var j = 0; j < rows.length; j++) {
      if (rowMatchesFilter(rows[j], filter || "all")
          && (search === "" || (String(rows[j].label) + " " + String(rows[j].id)).toLowerCase().indexOf(String(search).toLowerCase()) !== -1)) out.push(rows[j])
    }
  }
  var add = suggestions || [], needle = String(search || "").toLowerCase()
  for (var k = 0; k < add.length; k++) {
    if ((filter || "all") === "all" && (needle === "" || (String(add[k].pretty) + " " + String(add[k].id)).toLowerCase().indexOf(needle) !== -1)) out.push(add[k])
  }
  return out
}

function rangeIds(rows, anchor, target) {
  var a = -1, b = -1
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].id === anchor) a = i
    if (rows[i].id === target) b = i
  }
  if (a < 0 || b < 0) return target === undefined ? [] : [target]
  if (a > b) { var t = a; a = b; b = t }
  return rows.slice(a, b + 1).map(function(r) { return r.id })
}

// Copy the panel navigation state without retaining QML objects. Geometry is
// measured by the panel, while this value stays safe to compare in tests.
function navigationSnapshot(v) {
  var tabs = ["overview", "configs", "settings", "restore"]
  var scroll = {}, sourceScroll = v.scrollY || {}
  for (var i = 0; i < tabs.length; i++) scroll[tabs[i]] = Number(sourceScroll[tabs[i]]) || 0
  return {
    activeTab: tabs.indexOf(v.activeTab) >= 0 ? v.activeTab : "overview",
    scrollY: scroll,
    openCards: copyKeys(v.openCards),
    openRow: String(v.openRow || ""),
    openCommits: copyKeys(v.openCommits),
    fileSearch: String(v.fileSearch || ""),
    stateFilter: String(v.stateFilter || "all"),
    settingSearch: String(v.settingSearch || ""),
    settingFilter: String(v.settingFilter || "all"),
    manageMode: v.manageMode === true,
    selectedIds: (v.selectedIds || []).slice(),
    selectionAnchor: String(v.selectionAnchor || ""),
    focusIndex: Number(v.focusIndex !== undefined ? v.focusIndex : v.keyboardFocusIndex) || 0,
    manageCursor: Number(v.manageCursor) || 0,
    focus: v.focus && v.focus.id ? { kind: String(v.focus.kind || ""), id: String(v.focus.id) } : null,
    focusedField: String(v.focusedField || ""),
    anchor: v.anchor && v.anchor.id ? {
      kind: String(v.anchor.kind || "card"),
      id: String(v.anchor.id),
      offset: Number(v.anchor.offset) || 0
    } : null
  }
}

function copyKeys(value) {
  var out = {}
  var source = value || {}
  for (var k in source) if (source[k] === true) out[k] = true
  return out
}

function navigationScroll(snapshot, tab, maximum) {
  var raw = snapshot && snapshot.scrollY ? Number(snapshot.scrollY[tab]) || 0 : 0
  return Math.max(0, Math.min(raw, Math.max(0, Number(maximum) || 0)))
}

// Build the logical order used by the panel's keyboard cursor. The visual
// controls remain ordinary QML controls, but their order is stable and can be
// tested without a running shell.
function focusItems(tab, cards, rows, settings) {
  var out = [{ kind: "tab", id: "overview" }, { kind: "tab", id: "configs" },
             { kind: "tab", id: "settings" }, { kind: "tab", id: "restore" }]
  if (tab === "configs") {
    out.push({ kind: "filter", id: "configs-search" }, { kind: "filter", id: "configs-state" });
    (cards || []).forEach(function(card) {
      out.push({ kind: "card", id: String(card.id) })
      ;(card.rows || []).forEach(function(row) {
        out.push({ kind: "row", id: String(row.id) })
        if (row.sync_state === "incoming" || row.sync_state === "unsaved" || row.sync_state === "unpushed"
            || row.sync_state === "missing" || row.sync_state === "locked")
          out.push({ kind: "action", id: String(row.id) })
      })
    })
  } else if (tab === "settings") {
    out.push({ kind: "filter", id: "settings-search" }, { kind: "filter", id: "settings-state" })
    ;(settings || []).forEach(function(group) {
      out.push({ kind: "card", id: String(group.id) })
      ;(group.rows || []).forEach(function(row) {
        out.push({ kind: "row", id: String(row.id) })
      })
    })
  }
  return out
}

// The keyboard action for one row. Restore brings a newer or absent copy
// here, save commits this machine's version, and a locked secret has no local
// action until its key is imported. The visible primary button shows only
// Save and Restore; the keyboard reaches missing and locked rows too, so its
// action must not fall through to Save and fail there.
function keyboardActionFor(row) {
  var st = row ? row.sync_state : ""
  if (st === "incoming" || st === "missing") return "restore"
  if (st === "locked" || (row && row.locked === true)) return "locked"
  return "save"
}

function moveFocus(items, index, delta) {
  var list = items || [], max = list.length - 1
  if (max < 0) return 0
  var next = Number(index) + Number(delta)
  if (!(next >= 0)) next = 0
  return Math.max(0, Math.min(max, next))
}

function actionDisabledReason(facts) {
  var f = facts || {}
  if (f.busy === true) return "Another Replicant operation is running."
  if (f.ready !== true) return "Configure a repository first."
  if (f.available === false) return "This setting is not available in this machine's configuration."
  if (f.hasInput === false) return "Enter a file or folder path first."
  if (f.hasSelection === false) return "Select entries with the same supported operation."
  if (f.hasKey === false) return "Import the encryption key before managing secrets."
  return ""
}

function validBulkActions(rows) {
  var list = rows || []
  if (list.length === 0) return []
  if (list.some(function(r) { return r.locked === true || r.sync_state === "locked" })) return []
  if (list.every(function(r) { return r.suggestion === true })) {
    if (list.every(function(r) { return r.kind === "secret" })) return ["track-secret"]
    if (list.every(function(r) { return r.kind !== "secret" })) return ["track-config", "track-secret"]
    return []
  }
  var canSave = list.every(function(r) {
    return r.suggestion !== true && r.scope !== "off"
        && r.sync_state !== "off" && r.sync_state !== "pending"
        && r.sync_state !== "incoming" && r.sync_state !== "missing"
        && r.sync_state !== "locked"
  })
  var out = canSave ? ["save"] : []
  if (list.every(function(r) { return r.source === "user" && r.secret !== true })) out.push("convert-secret", "untrack")
  if (list.every(function(r) { return r.secret !== true })) out.push("scope-shared", "scope-profile", "scope-off")
  else if (list.every(function(r) { return r.secret === true })) out.push("scope-shared", "scope-off")
  return out
}

function bulkActionDescription(action) {
  if (action === "save") return "Save"
  if (action === "track-config") return "Track"
  if (action === "track-secret") return "Track as secret"
  if (action === "scope-shared") return "Set scope to Shared"
  if (action === "scope-profile") return "Set scope to Profile"
  if (action === "scope-off") return "Switch off"
  if (action === "convert-secret") return "Convert to secret"
  if (action === "untrack") return "Untrack"
  return "Apply change"
}

function selectionWithoutIds(selectedIds, selectionAnchor, removedIds) {
  var removed = removedIds || []
  var kept = (selectedIds || []).filter(function(id) { return removed.indexOf(id) < 0 })
  return {
    selectedIds: kept,
    selectionAnchor: removed.indexOf(selectionAnchor) < 0 ? String(selectionAnchor || "")
                                                           : (kept.length > 0 ? String(kept[kept.length - 1]) : "")
  }
}

function selectionFromJob(meta, excludedIds) {
  var source = meta || {}
  var selection = {
    selectedIds: (source.previousSelectedIds || []).slice(),
    selectionAnchor: String(source.previousSelectionAnchor || "")
  }
  return selectionWithoutIds(selection.selectedIds, selection.selectionAnchor, excludedIds || [])
}

// What a multi-selection holds. Secret rows count as files but never as
// bytes: the dialog names how much moves, while a secret's size stays
// undisclosed the way its content does.
function selectionSummary(rows) {
  var list = rows || [], files = 0, bytes = 0, secrets = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i].secret === true) { secrets += 1; files += 1; continue }
    files += Number(list[i].nfiles || (list[i].is_dir ? 0 : 1))
    bytes += Number(list[i].size || 0)
  }
  return { selected: list.length, files: files, bytes: bytes, secrets: secrets }
}

// ── rows ────────────────────────────────────────────────────────────────────
// Entry rows are the status contract.
function entryRows(repoState) {
  var out = []
  var list = repoState.entries || []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var secret = e.kind === "secret"
    out.push({
      id: e.id, label: e.label || e.id, src: e.src || "", category: e.category || "other",
      sync_state: e.sync_state, exists: e.exists === true, has_default: false,
      saved: e.saved === true, is_default: e.is_default === true,
      synced: e.scope !== "off", scope: e.scope || "shared", source: e.source || "override",
      is_dir: e.kind === "dir", nfiles: e.nfiles || 0,
      size: Number(e.size || 0),
      secret: secret, kind: secret ? "secret" : "", mode: "", vars: [], var_count: 0,
      locked: e.locked === true, incoming: e.incoming === true, unpushed: e.unpushed === true
    })
  }
  return out
}

function allRows(repoState) {
  return entryRows(repoState)
}

// The rows of one area in one uniform shape, secrets included, filtered by
// the search text and the state filter (rowMatchesFilter), and sorted by label.
function rowsForList(sourceRows, categoryId, search, filter) {
  var out = []
  var list = sourceRows || []
  var needle = String(search || "").toLowerCase()
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if ((c.category || "other") !== categoryId) continue
    out.push(c)
  }
  if (needle !== "") {
    out = out.filter(function(r) {
      return (String(r.label) + " " + String(r.src)).toLowerCase().indexOf(needle) !== -1
    })
  }
  if (filter && filter !== "all") out = out.filter(function(r) { return rowMatchesFilter(r, filter) })
  // Actionable rows stay above saved rows. The original index is the final
  // key, so equal labels retain the registry order.
  out = out.map(function(r, i) { return { row: r, index: i } })
  out.sort(function(a, b) {
    var aa = needsAttention(a.row.sync_state) ? 0 : 1
    var bb = needsAttention(b.row.sync_state) ? 0 : 1
    if (aa !== bb) return aa - bb
    var label = String(a.row.label).localeCompare(String(b.row.label))
    if (label !== 0) return label
    var id = String(a.row.id).localeCompare(String(b.row.id))
    return id !== 0 ? id : a.index - b.index
  })
  out = out.map(function(v) { return v.row })
  return out
}

function rowsFor(repoState, categoryId, search, filter, overrides) {
  return rowsForList(effectiveRows(repoState, overrides), categoryId, search, filter)
}

// ── plugins ─────────────────────────────────────────────────────────────────
// An origin the way a person reads it: no scheme, no .git, no trailing slash.
function originLabel(origin) {
  var s = String(origin || "").replace(/^[a-z+]+:\/\//, "").replace(/^git@([^:]+):/, "$1/")
  return s.replace(/\.git$/, "").replace(/\/$/, "")
}

// Every plugin of the payload, with where its settings live. A plugin that
// keeps its own file (~/.config/omarchy/<last segment of the id>.json) has a
// row in the Plugins card. A bar widget keeps its settings in its entry in
// shell.json, which the Desktop & bar area saves. Some plugins have neither.
function pluginRows(repoState) {
  var rows = ({})
  var list = repoState.entries || repoState.configs || []
  for (var i = 0; i < list.length; i++) rows[list[i].id] = list[i]
  return (repoState.plugins || []).map(function(p) {
    var short = String(p.id).split(".").pop()
    var altShort = short.replace(/^omarchy-/, "")
    var candidates = [
      "plugins/" + short + ".json",
      short + "/config.json",
      short + "/settings.json",
      short + ".json",
      altShort + "/config.json",
      altShort + "/settings.json",
      altShort + ".json",
      String(p.id) + "/config.json",
      String(p.id) + "/settings.json",
      String(p.id) + ".json"
    ]
    var matchedId = ""
    for (var j = 0; j < candidates.length; j++) {
      if (rows[candidates[j]]) { matchedId = candidates[j]; break }
    }
    if (!matchedId) {
      for (var k = 0; k < list.length; k++) {
        var entryId = list[k].id || ""
        if (list[k].category === "plugins" && (entryId.indexOf(short + "/") === 0 || entryId.indexOf(altShort + "/") === 0 || entryId.indexOf(String(p.id) + "/") === 0)) {
          matchedId = entryId
          break
        }
      }
    }
    var where = matchedId !== "" ? "file" : p.in_bar === true ? "bar" : "none"
    return { id: p.id, name: p.name || p.id, version: p.version || "", installed: p.installed === true,
             origin: p.origin || "", method: p.method || "", recorded: p.recorded === true,
             settings: where, settingsId: where === "file" ? matchedId : "" }
  })
}

// The words on the right of a plugin's row: where its settings are.
function pluginWhere(p) {
  if (!p.installed) return "not installed here"
  if (p.settings === "file") return "own settings file"
  if (p.settings === "bar") return "settings in shell.json"
  return "no settings"
}

// The line under a plugin's name: its version and where it comes from, as the
// repo records it. A plugin installed after the last save is not recorded yet.
function pluginDetail(p) {
  var v = p.version !== "" ? "v" + p.version + "  ·  " : ""
  if (p.installed && !p.recorded) return v + "not in your repo yet: the next save records it"
  if (p.origin === "") return v + "no origin: nothing can install it again"
  if (p.method === "clone") return v + "a copy of " + p.origin + ", edited here"
  return v + originLabel(p.origin)
}

// ── the reader and the result bar ───────────────────────────────────────────
// How the reader colours one line. "diff" is a unified diff. "output" is what a
// command printed, with the marks the CLI draws: ✓ done, ✗ failed, ! a warning,
// · skipped, » what a dry run would run.
function lineRole(line, kind) {
  var s = String(line || "")
  if (kind === "diff") {
    if (s.indexOf("+++") === 0 || s.indexOf("---") === 0) return "dim"
    var c = s.charAt(0)
    if (c === "+") return "add"
    if (c === "-") return "del"
    if (c === "@") return "hunk"
    if (c === "#") return "dim"
    return "fg"
  }
  var t = s.replace(/^\s+/, "")
  var indented = t !== s
  if (t.indexOf("==") === 0 || t.indexOf("──") === 0) return "head"
  // A section of `doctor`: one word or two, at the start of the line.
  if (!indented && /^[A-Z][A-Za-z ]{1,20}$/.test(t)) return "head"
  var m = t.charAt(0)
  if (m === "✓") return "ok"
  if (m === "✗" || / failed/.test(t)) return "bad"
  if (m === "!") return "warn"
  if (m === "·") return "dim"
  if (m === "»" || m === "→") return "accent"
  if (t.indexOf("@@") === 0) return "hunk"
  // The diff lines of a restore preview are indented under their file.
  if (indented && m === "+") return "add"
  if (indented && m === "-" && t.charAt(1) !== "-") return "del"
  return "fg"
}

// The one line the result bar shows. When a command worked, the last thing it
// said. When it failed, the first line (which names the action) and the last
// (which says why). The marks go, because the bar draws its own.
function resultLine(text, ok) {
  var lines = String(text || "").split("\n")
    .map(function(l) { return l.replace(/^[\s✓✗·!→»]+/, "").trim() })
    .filter(function(l) { return l !== "" })
  if (lines.length === 0) return ""
  if (ok || lines.length === 1) return lines[lines.length - 1]
  return lines[0] + ": " + lines[lines.length - 1]
}

// ── the safety net ──────────────────────────────────────────────────────────
// Newest per id: undo takes the newest, so a row per id is a row per button.
// The rest are counted, never listed: twelve rows of the same file is a wall,
// and only one of them is reachable. `backups` comes newest first.
function backupRows(backups) {
  var seen = ({}), out = []
  for (var i = 0; i < backups.length; i++) {
    var b = backups[i]
    if (seen[b.id]) { out[seen[b.id] - 1].older += 1; continue }
    seen[b.id] = out.push({ id: b.id, path: b.path, epoch: b.epoch,
                            state: b.state, older: 0 })
  }
  return out
}

// A backup's age in the words a person uses about one. The epoch is in the
// filename and says nothing; "3 days ago" is the whole question being asked.
// `now` is in seconds and exists for the tests.
function agoText(epoch, now) {
  var t = now === undefined ? Math.floor(Date.now() / 1000) : now
  var s = Math.max(0, t - epoch)
  if (s < 60) return "just now"
  if (s < 3600) return plural(Math.max(1, Math.floor(s / 60)), "minute") + " ago"
  if (s < 86400) return plural(Math.max(1, Math.floor(s / 3600)), "hour") + " ago"
  if (s < 604800) return plural(Math.max(1, Math.floor(s / 86400)), "day") + " ago"
  if (s < 2592000) return plural(Math.max(1, Math.floor(s / 604800)), "week") + " ago"
  if (s < 31536000) return plural(Math.max(1, Math.floor(s / 2592000)), "month") + " ago"
  return plural(Math.max(1, Math.floor(s / 31536000)), "year") + " ago"
}

// GitHub repository names use letters, numbers, dots, underscores and hyphens.
// Keep this client check useful, but let the CLI validate again before creation.
function repoNameValid(name) {
  var value = String(name || "").trim()
  return value.length > 0 && value.length <= 100 && value !== "." && value !== ".."
      && /^[A-Za-z0-9._-]+$/.test(value)
}

function repoTransportUrl(login, name, transport) {
  var owner = String(login || "")
  var repo = String(name || "")
  return transport === "ssh" ? "git@github.com:" + owner + "/" + repo + ".git"
                             : "https://github.com/" + owner + "/" + repo + ".git"
}

// ── G7 controller queue and progress ───────────────────────────────────────
// One queue for every controller process. Interactive jobs run before queued
// background refreshes; duplicate background jobs coalesce into one. An
// accepted user action is never discarded. The return is explicit.
function queueIsBackground(job) {
  return !!(job && job.meta && job.meta.background === true)
}

function queueSameCommand(a, b) {
  return String(JSON.stringify(a.command || [])) === String(JSON.stringify(b.command || []))
}

// A background refresh that keeps losing its turn never runs: interactive
// jobs always insert before it, so a steady stream of them starves it without
// bound. Background jobs are all read-only (status, log, suggestions), so a
// stale one may safely take one turn after waiting this long.
var MAX_BACKGROUND_WAIT_MS = 15000

function queueEnqueue(queue, job, now) {
  var list = (queue || []).slice()
  var t = now === undefined ? Date.now() : now
  var next = { job: job.job, command: (job.command || []).slice(), meta: job.meta || ({}),
               queuedAt: job.queuedAt !== undefined ? job.queuedAt : t }
  if (queueIsBackground(next)) {
    for (var i = 0; i < list.length; i++) {
      if (list[i].job === next.job && queueSameCommand(list[i], next)) return { queue: list, result: "coalesced" }
    }
    list.push(next)
    return { queue: list, result: "queued" }
  }
  var at = list.length
  for (var k = 0; k < list.length; k++) {
    if (queueIsBackground(list[k])) { at = k; break }
  }
  list.splice(at, 0, next)
  return { queue: list, result: "queued" }
}

// Which queued job runs next. Normally the head: interactive jobs already
// precede background ones from queueEnqueue. A background job waiting past
// the bound takes one turn instead of starving, then the head resumes.
function queueNextIndex(queue, now) {
  var list = queue || [], t = now === undefined ? Date.now() : now
  if (list.length === 0) return -1
  for (var i = 0; i < list.length; i++) {
    if (queueIsBackground(list[i]) && (t - (list[i].queuedAt !== undefined ? list[i].queuedAt : t)) >= MAX_BACKGROUND_WAIT_MS) return i
  }
  return 0
}

// Parse one stderr line of the --progress-json stream. Returns the event
// object for protocol 1 stage/result lines, or null for human text,
// malformed JSON, combined fragments and foreign lines. progressParserFeed
// assembles arbitrary chunks into lines before this runs.
function parseProgressLine(line) {
  var s = String(line || "").trim()
  if (s === "" || s.charAt(0) !== "{") return null
  var o
  try { o = JSON.parse(s) } catch (e) { return null }
  if (!o || o.protocol !== 1) return null
  if (o.type === "stage") {
    if (["run", "scan", "encrypt", "commit", "publish"].indexOf(o.stage) < 0) return null
    return { type: "stage", stage: o.stage, cancellable: o.cancellable === true,
             message: String(o.message || "") }
  }
  if (o.type === "result") {
    if (["success", "noop", "cancelled", "local-only", "failed"].indexOf(o.outcome) < 0) return null
    return { type: "result", outcome: o.outcome, message: String(o.message || ""),
             recoveryCommand: o.recoveryCommand === null ? null : String(o.recoveryCommand || "") }
  }
  return null
}

// Feed arbitrary stderr chunks into a newline-delimited progress parser.
// Keep incomplete data in state.buffer. Recognized protocol lines become
// events and disappear from the human output; malformed or foreign lines stay
// byte-for-byte in text. final flushes the last line when it has no newline.
function progressParserFeed(state, chunk, final) {
  var parser = state || ({ buffer: "" })
  parser.buffer = String(parser.buffer || "") + String(chunk || "")
  var events = [], text = "", at
  while ((at = parser.buffer.indexOf("\n")) >= 0) {
    var line = parser.buffer.slice(0, at)
    parser.buffer = parser.buffer.slice(at + 1)
    var event = parseProgressLine(line)
    if (event) events.push(event)
    else text += line + "\n"
  }
  if (final && parser.buffer !== "") {
    var last = parser.buffer
    parser.buffer = ""
    var finalEvent = parseProgressLine(last)
    if (finalEvent) events.push(finalEvent)
    else text += last
  }
  return { events: events, text: text }
}

// Map a protocol stage to the controller stage word the panel renders.
function progressStageWord(stage) {
  if (stage === "run") return "running"
  if (stage === "scan") return "scanning"
  if (stage === "encrypt") return "encrypting"
  if (stage === "commit") return "committing"
  if (stage === "publish") return "publishing"
  return "running"
}

// The nearest surviving row when the selected one disappears: the same id
// when it is still there, otherwise the row at the old index clamped into
// the new list, or "" when nothing remains.
function nearestRowId(rows, oldId, oldIndex) {
  var list = rows || []
  if (list.length === 0) return ""
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].id) === String(oldId)) return String(list[i].id)
  }
  var at = Math.max(0, Math.min(list.length - 1, Number(oldIndex) || 0))
  return String(list[at].id || "")
}

// Restore a multi-selection after a status refresh. Keep every surviving id.
// If the anchor survives, keep it; otherwise prefer a surviving selection
// near the old cursor, and select the nearest row only when none survives.
function restoreSelection(rows, selectedIds, selectionAnchor, oldIndex) {
  var list = rows || []
  var ids = selectedIds || []
  var kept = ids.filter(function(id) {
    return list.some(function(row) { return String(row.id) === String(id) })
  })
  var anchor = String(selectionAnchor || "")
  if (kept.indexOf(anchor) >= 0) return { selectedIds: kept, selectionAnchor: anchor }
  if (kept.length > 0) {
    var target = Number(oldIndex) || 0
    var bestId = kept[0], bestDistance = Infinity
    for (var i = 0; i < list.length; i++) {
      if (kept.indexOf(String(list[i].id)) < 0) continue
      var distance = Math.abs(i - target)
      if (distance < bestDistance) { bestDistance = distance; bestId = String(list[i].id) }
    }
    return { selectedIds: kept, selectionAnchor: bestId }
  }
  if (ids.length > 0 || anchor !== "") {
    var nearest = nearestRowId(list, anchor, oldIndex)
    return { selectedIds: nearest === "" ? [] : [nearest], selectionAnchor: nearest }
  }
  return { selectedIds: [], selectionAnchor: "" }
}

// Restore the logical keyboard focus by stable kind/id. If its row vanished,
// choose the row at the old keyboard position, clamped to the current rows.
function focusIndexFor(items, focus, fallback) {
  var list = items || []
  if (focus && focus.id) {
    for (var i = 0; i < list.length; i++) {
      if (list[i].kind === focus.kind && String(list[i].id) === String(focus.id)) return i
    }
    if (focus.kind === "row") {
      var rows = [], before = 0
      var target = Math.max(0, Number(fallback) || 0)
      for (var j = 0; j < list.length; j++) {
        if (list[j].kind !== "row") continue
        if (j < target) before++
        rows.push(j)
      }
      if (rows.length > 0) return rows[Math.min(rows.length - 1, before)]
    }
  }
  return Math.max(0, Math.min(Math.max(0, list.length - 1), Number(fallback) || 0))
}

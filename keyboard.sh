#!/usr/bin/env bash
# ============================================================
# keyboard.sh - Ubuntu Keyboard Layer
#
# Run it:        ./keyboard.sh
# Or directly:   ./keyboard.sh apply | remove | status | preview
#
# You should never need to edit this file.
# Everything you can change lives in keybindings.conf.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${KEYBOARD_CONF:-$SCRIPT_DIR/keybindings.conf}"

# Backups live outside the repo so they never get committed.
STATE_DIR="${XDG_STATE_HOME:-${HOME:-}/.local/state}/ubuntu-keyboard-layer"
BACKUP_FILE="$STATE_DIR/backup.tsv"   # lines: schema <TAB> key <TAB> original value

WM_SCHEMA="org.gnome.desktop.wm.keybindings"
MUTTER_KB_SCHEMA="org.gnome.mutter.keybindings"
SHELL_KB_SCHEMA="org.gnome.shell.keybindings"
MEDIA_SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
DOCK_SCHEMA="org.gnome.shell.extensions.dash-to-dock"
CUSTOM_SCHEMA="$MEDIA_SCHEMA.custom-keybinding"
CUSTOM_BASE="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
CUSTOM_ID_PREFIX="ubuntu-keyboard-"

# Schemas scanned for shortcuts that would collide with yours.
SCAN_SCHEMAS=(
    "$WM_SCHEMA" "$MUTTER_KB_SCHEMA" "org.gnome.mutter.wayland.keybindings"
    "$SHELL_KB_SCHEMA" "$MEDIA_SCHEMA" "$DOCK_SCHEMA"
)

US=$'\x1f'      # field separator for internal records
DRY_RUN=0

# ------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

confirm() {   # ask only when a person is at the keyboard
    [[ -t 0 ]] || return 0
    local reply
    read -r -p "$1 [y/N] " reply || return 1
    [[ $reply == [yY]* ]]
}

require_session() {
    [[ $EUID -ne 0 ]] \
        || die "Do not run this as root or with sudo. It changes YOUR desktop settings."
    [[ -n "${HOME:-}" ]] || die "HOME is not set."
    command -v gsettings >/dev/null 2>&1 \
        || die "gsettings not found. This needs a GNOME desktop (Ubuntu)."
    command -v python3 >/dev/null 2>&1 \
        || die "python3 not found. Install it with: sudo apt install python3"
    [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] \
        || die "No desktop session found. Run this from a terminal inside your desktop session (not over SSH)."
    gsettings get "$WM_SCHEMA" close >/dev/null 2>&1 \
        || die "Cannot read GNOME settings. Is this a GNOME desktop?"
    [[ ${XDG_CURRENT_DESKTOP:-GNOME} == *GNOME* ]] \
        || warn "This does not look like a GNOME session ($XDG_CURRENT_DESKTOP). Continuing anyway."
}

gs_set() {
    if (( DRY_RUN )); then
        printf '  [preview] gsettings set %s %s %s\n' "$1" "$2" "$3"
    else
        gsettings set "$1" "$2" "$3"
    fi
}

gs_reset() {
    if (( DRY_RUN )); then
        printf '  [preview] gsettings reset %s %s\n' "$1" "$2"
    else
        gsettings reset "$1" "$2" 2>/dev/null || true
    fi
}

# Quote a string as a GVariant string literal.
gv_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\'/\\\'}"
    printf "'%s'" "$s"
}

SCHEMAS_CACHE=""
schema_exists() {
    [[ -n $SCHEMAS_CACHE ]] \
        || SCHEMAS_CACHE=" $(gsettings list-schemas | tr '\n' ' ') "
    [[ $SCHEMAS_CACHE == *" $1 "* ]]
}

declare -A KEYS_CACHE=()
key_exists() {
    local schema="$1" key="$2"
    if [[ -z "${KEYS_CACHE[$schema]+x}" ]]; then
        KEYS_CACHE[$schema]=" $(gsettings list-keys "$schema" 2>/dev/null | tr '\n' ' ') "
    fi
    [[ ${KEYS_CACHE[$schema]} == *" $key "* ]]
}

# ------------------------------------------------------------
# Backup / restore
#
# Before a setting is changed for the first time, its original
# value is recorded. Remove (and every re-run of Apply) puts the
# originals back. Every change goes through backup_key first, so
# nothing can be forgotten.
# ------------------------------------------------------------

backup_has() {
    [[ -f $BACKUP_FILE ]] || return 1
    local s k v
    while IFS=$'\t' read -r s k v; do
        if [[ $s == "$1" && $k == "$2" ]]; then return 0; fi
    done < "$BACKUP_FILE"
    return 1
}

backup_key() {
    mkdir -p "$STATE_DIR"
    backup_has "$1" "$2" && return 0
    printf '%s\t%s\t%s\n' "$1" "$2" "$(gsettings get "$1" "$2")" >> "$BACKUP_FILE"
}

original_value() {   # value before we touched it
    local s k v
    if [[ -f $BACKUP_FILE ]]; then
        while IFS=$'\t' read -r s k v; do
            if [[ $s == "$1" && $k == "$2" ]]; then
                printf '%s' "$v"
                return 0
            fi
        done < "$BACKUP_FILE"
    fi
    gsettings get "$1" "$2"
}

restore_backup() {
    [[ -s $BACKUP_FILE ]] || return 0
    local s k v n=0
    while IFS=$'\t' read -r s k v; do
        [[ -n $s ]] || continue
        if gs_set "$s" "$k" "$v" 2>/dev/null; then
            n=$((n + 1))
        else
            warn "could not restore $s $k"
        fi
    done < "$BACKUP_FILE"
    say "  restored $n original settings"
}

# ------------------------------------------------------------
# Custom shortcuts we own (ids start with ubuntu-keyboard-).
# Shortcuts you created yourself are never touched.
# ------------------------------------------------------------

# custom_list <managed|without|with> <raw value> [paths to add]
custom_list() {
    python3 - "$@" "$CUSTOM_BASE/$CUSTOM_ID_PREFIX" <<'PY'
import ast, sys

mode, raw = sys.argv[1], sys.argv[2]
prefix = sys.argv[-1]
adds = sys.argv[3:-1]

items = [] if raw.startswith("@as") else ast.literal_eval(raw)
managed = [p for p in items if p.startswith(prefix)]
others = [p for p in items if not p.startswith(prefix)]

if mode == "managed":
    print("\n".join(managed))
elif mode == "without":
    print(repr(others))
else:
    print(repr(others + sorted(adds)))
PY
}

remove_managed_custom() {
    local raw path k
    raw="$(gsettings get "$MEDIA_SCHEMA" custom-keybindings)"
    while IFS= read -r path; do
        [[ -n $path ]] || continue
        for k in name command binding; do
            gs_reset "$CUSTOM_SCHEMA:$path" "$k"
        done
    done < <(custom_list managed "$raw")
    gs_set "$MEDIA_SCHEMA" custom-keybindings "$(custom_list without "$raw")"
}

has_managed_custom() {
    local raw
    raw="$(gsettings get "$MEDIA_SCHEMA" custom-keybindings)"
    [[ -n "$(custom_list managed "$raw")" ]]
}

# ------------------------------------------------------------
# Python helpers for shortcut lists
# ------------------------------------------------------------

# merge_bindings <additive|takeover> <original value> <binding>...
merge_bindings() {
    python3 - "$@" <<'PY'
import ast, re, sys

ALIAS = {"primary": "control", "ctrl": "control"}

def norm(b):
    mods = {ALIAS.get(m.lower(), m.lower()) for m in re.findall(r"<([^>]+)>", b)}
    return (frozenset(mods), re.sub(r"<[^>]+>", "", b).lower())

mode, original, *ours = sys.argv[1:]
orig = [] if original.startswith("@as") else ast.literal_eval(original)
result = [] if mode == "takeover" else list(orig)
have = {norm(b) for b in result}
for b in ours:
    if norm(b) not in have:
        result.append(b)
        have.add(norm(b))
print(repr(result))
PY
}

# find_conflicts <dump file> <managed "schema:key ..."> <binding>...
# Prints: schema <TAB> key <TAB> new value <TAB> removed bindings
find_conflicts() {
    python3 - "$@" <<'PY'
import ast, re, sys

ALIAS = {"primary": "control", "ctrl": "control"}

def norm(b):
    mods = {ALIAS.get(m.lower(), m.lower()) for m in re.findall(r"<([^>]+)>", b)}
    return (frozenset(mods), re.sub(r"<[^>]+>", "", b).lower())

dump, managed = sys.argv[1], set(sys.argv[2].split())
ours = {norm(b) for b in sys.argv[3:]}

for line in open(dump):
    parts = line.rstrip("\n").split(" ", 2)
    if len(parts) < 3:
        continue
    schema, key, val = parts
    if f"{schema}:{key}" in managed:
        continue
    try:
        lst = [] if val.startswith("@as") else ast.literal_eval(val)
    except Exception:
        continue
    if not isinstance(lst, list) or not all(isinstance(x, str) for x in lst):
        continue
    kept = [b for b in lst if norm(b) not in ours]
    if len(kept) != len(lst):
        removed = " ".join(b for b in lst if norm(b) in ours)
        print(f"{schema}\t{key}\t{kept!r}\t{removed}")
PY
}

# has_binding <raw list value> <binding>  (ignores modifier order)
has_binding() {
    python3 - "$@" <<'PY'
import ast, re, sys

ALIAS = {"primary": "control", "ctrl": "control"}

def norm(b):
    mods = {ALIAS.get(m.lower(), m.lower()) for m in re.findall(r"<([^>]+)>", b)}
    return (frozenset(mods), re.sub(r"<[^>]+>", "", b).lower())

raw, binding = sys.argv[1], sys.argv[2]
try:
    lst = [] if raw.startswith("@as") else ast.literal_eval(raw)
except Exception:
    sys.exit(1)
sys.exit(0 if norm(binding) in {norm(x) for x in lst} else 1)
PY
}

# ------------------------------------------------------------
# Config parsing
# ------------------------------------------------------------

# "SUPER+SHIFT+S" -> "<Super><Shift>s".  Fails on anything unknown.
to_gnome_key() {
    local spec="${1^^}" out="" part i
    local -a parts
    spec="${spec// /}"
    IFS='+' read -ra parts <<< "$spec"
    (( ${#parts[@]} >= 1 )) || return 1
    for (( i = 0; i < ${#parts[@]}; i++ )); do
        part="${parts[i]}"
        if (( i < ${#parts[@]} - 1 )); then
            case "$part" in
                SUPER)        out+="<Super>"   ;;
                CTRL|CONTROL) out+="<Control>" ;;
                ALT)          out+="<Alt>"     ;;
                SHIFT)        out+="<Shift>"   ;;
                *) return 1 ;;
            esac
        else
            case "$part" in
                ENTER)    out+="Return"    ;;
                ESC)      out+="Escape"    ;;
                TAB)      out+="Tab"       ;;
                SPACE)    out+="space"     ;;
                UP)       out+="Up"        ;;
                DOWN)     out+="Down"      ;;
                LEFT)     out+="Left"      ;;
                RIGHT)    out+="Right"     ;;
                PAGEUP)   out+="Page_Up"   ;;
                PAGEDOWN) out+="Page_Down" ;;
                F[1-9]|F1[0-2]) out+="$part" ;;
                [A-Z])    out+="${part,,}" ;;
                [0-9])    out+="$part"     ;;
                *) return 1 ;;
            esac
        fi
    done
    printf '%s' "$out"
}

# Sets R_KIND (gs|custom), R_SCHEMA, R_KEY, R_CMD for an action name.
resolve_action() {
    local action="$1" s k
    R_KIND="" R_SCHEMA="" R_KEY="" R_CMD=""
    case "$action" in
        close|minimize|maximize|toggle-maximized|toggle-fullscreen)
            R_KIND=gs; R_SCHEMA=$WM_SCHEMA; R_KEY=$action ;;
        tile:left|tile:right)
            R_KIND=gs; R_SCHEMA=$MUTTER_KB_SCHEMA; R_KEY="toggle-tiled-${action#tile:}" ;;
        move-to-monitor:left|move-to-monitor:right|move-to-monitor:up|move-to-monitor:down)
            R_KIND=gs; R_SCHEMA=$WM_SCHEMA; R_KEY="move-to-monitor-${action#move-to-monitor:}" ;;
        workspace:last)
            R_KIND=gs; R_SCHEMA=$WM_SCHEMA; R_KEY="switch-to-workspace-last" ;;
        workspace:[1-9]|workspace:1[0-2])
            R_KIND=gs; R_SCHEMA=$WM_SCHEMA; R_KEY="switch-to-workspace-${action#workspace:}" ;;
        move-to-workspace:last)
            R_KIND=gs; R_SCHEMA=$WM_SCHEMA; R_KEY="move-to-workspace-last" ;;
        move-to-workspace:[1-9]|move-to-workspace:1[0-2])
            R_KIND=gs; R_SCHEMA=$WM_SCHEMA; R_KEY="move-to-workspace-${action#move-to-workspace:}" ;;
        overview)
            R_KIND=gs; R_SCHEMA=$SHELL_KB_SCHEMA; R_KEY="toggle-overview" ;;
        apps)
            R_KIND=gs; R_SCHEMA=$SHELL_KB_SCHEMA; R_KEY="toggle-application-view" ;;
        notifications)
            R_KIND=gs; R_SCHEMA=$SHELL_KB_SCHEMA; R_KEY="toggle-message-tray" ;;
        screenshot)
            R_KIND=gs; R_SCHEMA=$SHELL_KB_SCHEMA; R_KEY="show-screenshot-ui" ;;
        lock)
            R_KIND=gs; R_SCHEMA=$MEDIA_SCHEMA; R_KEY="screensaver" ;;
        terminal)
            R_KIND=custom; R_CMD="x-terminal-emulator" ;;
        files)
            R_KIND=custom; R_CMD="nautilus" ;;
        browser)
            R_KIND=custom; R_CMD="sh -c 'gtk-launch \$(xdg-settings get default-web-browser)'" ;;
        exec:?*)
            R_KIND=custom; R_CMD="${action#exec:}" ;;
        gsettings:?*)
            read -r s k _ <<< "${action#gsettings:}"
            [[ -n ${s:-} && -n ${k:-} ]] || return 1
            R_KIND=gs; R_SCHEMA=$s; R_KEY=$k ;;
        *) return 1 ;;
    esac
}

parse_config() {
    [[ -f $CONFIG_FILE ]] || die "Config not found: $CONFIG_FILE"

    MODE="additive"
    declare -gA SEEN_KEYS=() SEEN_BINDS=() GROUP_BINDINGS=()
    GS_ENTRIES=() CU_ENTRIES=()
    CUSTOM_IDS=() CUSTOM_NAMES=() CUSTOM_CMDS=() CUSTOM_BINDS=()
    ALL_BINDINGS=()
    MANAGED=""

    local line lineno=0 lhs rhs keyname binding gk id
    while IFS= read -r line || [[ -n $line ]]; do
        lineno=$((lineno + 1))
        line="${line%$'\r'}"
        line="${line%%#*}"
        line="$(trim "$line")"
        [[ -z $line ]] && continue

        [[ $line == *=* ]] \
            || die "keybindings.conf line $lineno: expected 'KEYS = ACTION', got: $line"
        lhs="$(trim "${line%%=*}")"
        rhs="$(trim "${line#*=}")"
        [[ -n $lhs && -n $rhs ]] \
            || die "keybindings.conf line $lineno: both sides of '=' are required"

        if [[ $lhs == @* ]]; then
            case "$lhs" in
                @mode)
                    case "$rhs" in
                        additive|takeover) MODE="$rhs" ;;
                        *) die "keybindings.conf line $lineno: @mode must be 'additive' or 'takeover'" ;;
                    esac ;;
                *) die "keybindings.conf line $lineno: unknown setting '$lhs'" ;;
            esac
            continue
        fi

        keyname="${lhs^^}"; keyname="${keyname// /}"
        binding="$(to_gnome_key "$keyname")" \
            || die "keybindings.conf line $lineno: unrecognised key '$lhs' (see the header of keybindings.conf)"
        [[ -z ${SEEN_KEYS[$keyname]:-} && -z ${SEEN_BINDS[$binding]:-} ]] \
            || die "keybindings.conf line $lineno: '$lhs' is used more than once"
        SEEN_KEYS[$keyname]=1
        SEEN_BINDS[$binding]=1

        resolve_action "$rhs" \
            || die "keybindings.conf line $lineno: unknown action '$rhs' (see the header of keybindings.conf)"

        if [[ $R_KIND == gs ]]; then
            if ! key_exists "$R_SCHEMA" "$R_KEY"; then
                warn "skipping '$keyname = $rhs': $R_SCHEMA $R_KEY does not exist on this system"
                continue
            fi
            gk="$R_SCHEMA|$R_KEY"
            GROUP_BINDINGS[$gk]+="${GROUP_BINDINGS[$gk]:+ }$binding"
            GS_ENTRIES+=("$keyname$US$rhs$US$R_SCHEMA$US$R_KEY$US$binding")
            MANAGED+="$R_SCHEMA:$R_KEY "
        else
            id="${CUSTOM_ID_PREFIX}$(printf '%s' "${keyname,,}" | tr '+' '-')"
            CUSTOM_IDS+=("$id")
            CUSTOM_NAMES+=("Keyboard Layer: $keyname")
            CUSTOM_CMDS+=("$R_CMD")
            CUSTOM_BINDS+=("$binding")
            CU_ENTRIES+=("$keyname$US$rhs$US$id$US$binding")
        fi
        ALL_BINDINGS+=("$binding")
    done < "$CONFIG_FILE"

    (( ${#GS_ENTRIES[@]} + ${#CU_ENTRIES[@]} > 0 )) \
        || die "No shortcuts found in $CONFIG_FILE"
}

# Sets CHECK_OK (count) and CHECK_BAD (list) by reading live settings.
check_entries() {
    CHECK_OK=0
    CHECK_BAD=()
    local e keyname rhs schema key binding id cur
    for e in "${GS_ENTRIES[@]}"; do
        IFS="$US" read -r keyname rhs schema key binding <<< "$e"
        cur="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
        if has_binding "$cur" "$binding"; then
            CHECK_OK=$((CHECK_OK + 1))
        else
            CHECK_BAD+=("$keyname = $rhs")
        fi
    done
    for e in "${CU_ENTRIES[@]}"; do
        IFS="$US" read -r keyname rhs id binding <<< "$e"
        cur="$(gsettings get "$CUSTOM_SCHEMA:$CUSTOM_BASE/$id/" binding 2>/dev/null || true)"
        if [[ $cur == "'$binding'" ]]; then
            CHECK_OK=$((CHECK_OK + 1))
        else
            CHECK_BAD+=("$keyname = $rhs")
        fi
    done
}

# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------

do_apply() {
    parse_config
    say
    if (( DRY_RUN )); then
        say "PREVIEW - nothing will be changed."
    else
        say "Applying keybindings.conf  (mode: $MODE)"
    fi

    if (( ! DRY_RUN )); then
        if [[ -f "$SCRIPT_DIR/.state/gnome-state.sh" && ! -s $BACKUP_FILE ]]; then
            warn "An older version of this layer was applied on this machine."
            say  "  Its changes can't be told apart from your own settings, so they"
            say  "  would be treated as your 'original' shortcuts. For a clean start,"
            say  "  reset the affected groups to Ubuntu defaults first (this resets ALL"
            say  "  shortcuts in them):"
            say  "    for s in org.gnome.desktop.wm.keybindings org.gnome.shell.keybindings \\"
            say  "             org.gnome.mutter.keybindings $MEDIA_SCHEMA \\"
            say  "             $DOCK_SCHEMA; do gsettings reset-recursively \$s; done"
            confirm "Continue anyway?" || { say "Cancelled."; return 0; }
        fi
        # Start every apply from the original state, so editing the
        # config and re-applying always gives a clean result.
        restore_backup
        remove_managed_custom
    fi

    # --- Built-in GNOME shortcuts -------------------------------
    local gk schema key orig new
    for gk in "${!GROUP_BINDINGS[@]}"; do
        schema="${gk%%|*}"
        key="${gk#*|}"
        (( DRY_RUN )) || backup_key "$schema" "$key"
        orig="$(original_value "$schema" "$key")"
        if [[ $orig != \[* && $orig != @as* ]]; then
            warn "skipping $schema $key: not a shortcut list"
            continue
        fi
        # shellcheck disable=SC2086   # bindings never contain spaces or globs
        new="$(merge_bindings "$MODE" "$orig" ${GROUP_BINDINGS[$gk]})"
        gs_set "$schema" "$key" "$new"
    done

    # --- Shortcuts that launch commands -------------------------
    local i path
    local -a our_paths=()
    for i in "${!CUSTOM_IDS[@]}"; do
        path="$CUSTOM_BASE/${CUSTOM_IDS[$i]}/"
        gs_set "$CUSTOM_SCHEMA:$path" name    "$(gv_str "${CUSTOM_NAMES[$i]}")"
        gs_set "$CUSTOM_SCHEMA:$path" command "$(gv_str "${CUSTOM_CMDS[$i]}")"
        gs_set "$CUSTOM_SCHEMA:$path" binding "$(gv_str "${CUSTOM_BINDS[$i]}")"
        our_paths+=("$path")
    done
    if (( ${#our_paths[@]} > 0 )); then
        gs_set "$MEDIA_SCHEMA" custom-keybindings \
            "$(custom_list with "$(gsettings get "$MEDIA_SCHEMA" custom-keybindings)" "${our_paths[@]}")"
    fi

    # --- Free keys that GNOME already uses for something else ----
    local dump s k newval removed freed=0 dock_conflict=0
    dump="$(mktemp)"
    for s in "${SCAN_SCHEMAS[@]}"; do
        if schema_exists "$s"; then gsettings list-recursively "$s" >> "$dump"; fi
    done
    while IFS=$'\t' read -r s k newval removed; do
        [[ -n $s ]] || continue
        (( DRY_RUN )) || backup_key "$s" "$k"
        gs_set "$s" "$k" "$newval"
        say "  freed $removed (GNOME used it for: $k)"
        freed=$((freed + 1))
        [[ $s == "$DOCK_SCHEMA" ]] && dock_conflict=1
    done < <(find_conflicts "$dump" "$MANAGED" "${ALL_BINDINGS[@]}")
    rm -f "$dump"

    if (( dock_conflict )) && key_exists "$DOCK_SCHEMA" hot-keys; then
        (( DRY_RUN )) || backup_key "$DOCK_SCHEMA" hot-keys
        gs_set "$DOCK_SCHEMA" hot-keys false
    fi

    # --- Report -------------------------------------------------
    say
    if (( DRY_RUN )); then
        say "Preview done. Choose Apply to make these changes."
        return 0
    fi
    check_entries
    if (( ${#CHECK_BAD[@]} > 0 )); then
        warn "${#CHECK_BAD[@]} shortcut(s) did not take effect:"
        printf '    %s\n' "${CHECK_BAD[@]}" >&2
    fi
    say "Done: $CHECK_OK shortcut(s) active, $freed conflicting default(s) freed."
    say "Pressing Super alone still opens the overview/search (unchanged)."
    say "Undo anytime:  ./keyboard.sh remove"
}

do_remove() {
    say
    if [[ ! -s $BACKUP_FILE ]] && ! has_managed_custom; then
        say "Nothing to remove - this layer is not applied."
        return 0
    fi
    say "Removing the keyboard layer..."
    if [[ ! -s $BACKUP_FILE ]]; then
        warn "No backup found, so original settings cannot be restored."
        say  "  Only the launcher shortcuts this tool created will be removed."
    fi
    restore_backup
    remove_managed_custom
    if [[ -f $BACKUP_FILE && $DRY_RUN -eq 0 ]]; then
        mv -f "$BACKUP_FILE" "$BACKUP_FILE.restored"
    fi
    say
    say "Done. Your previous shortcuts are back."
}

do_status() {
    parse_config
    say
    say "Config:  $CONFIG_FILE"
    say "Mode:    $MODE"
    if [[ -s $BACKUP_FILE ]]; then
        say "Backup:  $BACKUP_FILE"
    else
        say "Backup:  none (layer not applied)"
    fi
    check_entries
    say "Active:  $CHECK_OK of $((CHECK_OK + ${#CHECK_BAD[@]})) shortcuts from the config"
    if (( ${#CHECK_BAD[@]} > 0 )); then
        say
        say "Not active:"
        printf '  %s\n' "${CHECK_BAD[@]}"
        say
        say "Choose Apply to fix."
    fi
}

# ------------------------------------------------------------
# Entry point
# ------------------------------------------------------------

usage() {
    cat <<'EOF'
Ubuntu Keyboard Layer

Usage:
  ./keyboard.sh             interactive menu
  ./keyboard.sh apply       apply keybindings.conf
  ./keyboard.sh remove      restore your original shortcuts
  ./keyboard.sh status      show what is active
  ./keyboard.sh preview     show what apply would change (changes nothing)

To customise, edit keybindings.conf, then run apply again.
EOF
}

menu() {
    local choice
    while true; do
        cat <<'EOF'

==============================================
  Ubuntu Keyboard Layer
==============================================
  1) Apply    install the shortcuts in keybindings.conf
  2) Remove   restore your original shortcuts
  3) Status   show what is currently active
  4) Preview  show what Apply would change (no changes)
  q) Quit

EOF
        read -r -p "Choose: " choice || exit 0
        case "$choice" in
            1) DRY_RUN=0; do_apply;  return ;;
            2) DRY_RUN=0; do_remove; return ;;
            3) do_status ;;
            4) DRY_RUN=1; do_apply; DRY_RUN=0 ;;
            q|Q) exit 0 ;;
            *) say "Please choose 1, 2, 3, 4 or q." ;;
        esac
    done
}

main() {
    case "${1:-}" in
        -h|--help|help) usage; exit 0 ;;
    esac

    require_session

    case "${1:-}" in
        apply)             do_apply ;;
        remove)            do_remove ;;
        status)            do_status ;;
        preview|--dry-run) DRY_RUN=1; do_apply ;;
        "")
            if [[ -t 0 ]]; then menu; else usage; exit 1; fi ;;
        *) usage; die "Unknown command: $1" ;;
    esac
}

main "$@"

#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  termwrap (tw) — sandboxed command execution for Termux on UNROOTED Android
#
#  bubblewrap-style ergonomics, proot/ptrace mechanics.
#  No root. No user namespaces. No kernel patches.
#
#  Why not bwrap? bubblewrap needs CONFIG_USER_NS + unprivileged namespace
#  creation; stock Android kernels ship with that disabled / SELinux-blocked.
#  termwrap gets isolation from a different primitive: ptrace(2) via proot,
#  plus a few honest side-channels (LD_PRELOAD netblock, ulimits, timeout,
#  tar-jailed copies of $PREFIX for destructive-proof runs).
#
#  License: MIT. Threat model: AI agents & semi-trusted automation, NOT
#  actively malicious native code (see: tw --caveats).
#
#  COPYRIGHT OPENTODO© — released under the MIT license.
# =============================================================================

set -uo pipefail

readonly TW_VERSION="0.1.0"
readonly TW_NAME="termwrap"

# --------------------------------------------------------------------------
# locations
# --------------------------------------------------------------------------
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
TW_HOME="${TW_HOME:-$HOME/.local/share/termwrap}"
TW_LIB="$PREFIX/lib/termwrap"
TW_SHARE="$PREFIX/share/termwrap"
TW_PROFILES_USR="$TW_HOME/profiles.d"
TW_PROFILES_SYS="$TW_SHARE/profiles"
NETBLOCK_SO="${TW_NETBLOCK_SO:-$TW_LIB/netblock.so}"

# --------------------------------------------------------------------------
# pretty output
# --------------------------------------------------------------------------
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  C_GRN=$'\033[38;5;114m'; C_CYN=$'\033[38;5;81m'; C_RED=$'\033[38;5;203m'
  C_AMB=$'\033[38;5;215m'; C_DIM=$'\033[2m';       C_RST=$'\033[0m'
else
  C_GRN=""; C_CYN=""; C_RED=""; C_AMB=""; C_DIM=""; C_RST=""
fi
say()  { printf '%s::%s %s\n'  "$C_CYN" "$C_RST" "$*" >&2; }
ok()   { printf '%s[ok]%s %s\n' "$C_GRN" "$C_RST" "$*" >&2; }
warn() { printf '%s[!]%s  %s\n' "$C_AMB" "$C_RST" "$*" >&2; }
err()  { printf '%s[x]%s  %s\n' "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }
dbg()  { [[ "${TW_DEBUG:-0}" == 1 ]] && printf '%s[dbg]%s %s\n' "$C_DIM" "$C_RST" "$*" >&2; return 0; }

# --------------------------------------------------------------------------
# run state (defaults)
# --------------------------------------------------------------------------
BOX_NAME="default"      # persistent named home under $TW_HOME/home/<name>
EPHEMERAL=0             # fresh home per run, wiped on exit
JAIL=""                 # name of a tar-snapshot jail bound over $PREFIX
EPHEMERAL_JAIL=0        # copy jail per run, discard after (slow, paranoid)
ROOTFS=""               # raw proot -r rootfs (advanced)
FAKE_ROOT=1             # proot -0
NETBLOCK=0              # LD_PRELOAD socket shim
CLEARENV=0
FRESH_TMP=1             # overlay empty dir over $PREFIX/tmp
TIMEOUT=0               # seconds; 0 = none
NICE_L=0                # nice level 0..19
LIM_PROCS=""; LIM_FILES=""; LIM_FSIZE=""; LIM_MEM=""   # ulimits (MB space / counts)
AUDIT=""                # audit log file (proot -v)
DRY_RUN=0
ALLOW_NESTED=0
QUIET=0
PROFILE_DEPTH=0
GCWD=""                 # guest working dir (default: guest $HOME)
SCRIPT_FILE=""          # host file to bind+run inside
SANDBOX_LABEL=""        # custom id label
PROOT_V=9               # verbosity when auditing

# accumulators
USER_BINDS=()   # "src" or "src:dst"  (rw)
USER_RBINDS=()  # read-only binds (mode: chmod snapshot, best effort)
USER_DEVB=()    # device binds (same mechanism, kept for flag parity)
HIDES=()        # guest paths to shadow
TMPFS_PATHS=()  # guest paths to receive empty-dir overlays
ENVS=()         # K=V
UNSETS=()       # K
CMD=()          # command to execute

# cleanup registries
CLEAN_TMPDIRS=()
CLEAN_RO=()
CLEAN_EPH_HOME=""
CHILD_PID=""

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
need_arg() { [[ $# -ge 2 && -n ${2:-} ]] || die "flag $1 needs an argument"; }

expand_path() {  # echoes expanded path, ~ aware, made absolute against $PWD
  local p="$1"
  case "$p" in
    "~")   p="$HOME" ;;
    "~/"*) p="$HOME/${p#~/}" ;;
  esac
  [[ "$p" != /* ]] && p="$PWD/$p"
  printf '%s' "$p"
}

mktmpdir() {  # make + register a temp dir
  local d; d="$(mktemp -d "$TW_HOME/tmp/tw.XXXXXX")" || die "mktemp failed"
  CLEAN_TMPDIRS+=("$d"); printf '%s' "$d"
}

rand_id() { od -An -tx1 -N3 /dev/urandom 2>/dev/null | tr -d ' \n'; }

jail_dir() { printf '%s/jails/%s' "$TW_HOME" "$1"; }

valid_name() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,31}$ ]] || die "invalid name: '$1' (a-z 0-9 . _ -)"; }

# --------------------------------------------------------------------------
# profile loading (--profile NAME|FILE)
# fills the global array PROFILE_TOKENS for re-injection by the parser
# --------------------------------------------------------------------------
PROFILE_TOKENS=()
collect_profile() {
  local q="$1" f=""
  if   [[ -f "$q" ]];                       then f="$q"
  elif [[ -f "$TW_PROFILES_USR/$q.conf" ]]; then f="$TW_PROFILES_USR/$q.conf"
  elif [[ -f "$TW_PROFILES_USR/$q" ]];      then f="$TW_PROFILES_USR/$q"
  elif [[ -f "$TW_PROFILES_SYS/$q.conf" ]]; then f="$TW_PROFILES_SYS/$q.conf"
  elif [[ -f "$TW_PROFILES_SYS/$q" ]];      then f="$TW_PROFILES_SYS/$q"
  else die "profile not found: $q (looked in ~/$TW_PROFILES_USR and $TW_PROFILES_SYS)"
  fi
  PROFILE_DEPTH=$((PROFILE_DEPTH+1))
  [[ $PROFILE_DEPTH -gt 4 ]] && die "profile recursion too deep ($q)"
  PROFILE_TOKENS=(); local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                      # strip comments
    [[ -z "${line//[[:space:]]/}" ]] && continue
    # shellcheck disable=SC2206
    PROFILE_TOKENS+=($line)                  # intentional word-split
  done < "$f"
  [[ $QUIET == 0 ]] && say "profile ${C_GRN}${q}${C_RST} ← ${C_DIM}$f${C_RST} (${#PROFILE_TOKENS[@]} flags)"
  dbg "profile tokens: ${PROFILE_TOKENS[*]:-none}"
}

# --------------------------------------------------------------------------
# argument parser (bwrap-flavoured)
# --------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    # normalise  --flag=value  ->  --flag value
    if [[ "$1" == --*=* ]]; then set -- "${1%%=*}" "${1#*=}" "${@:2}"; fi
    case "${1:-}" in
      --) shift; CMD=("$@"); return 0 ;;
      -h|--help)     usage; exit 0 ;;
      -V|--version)  printf 'termwrap (tw) v%s — ptrace sandbox for unrooted Android\n' "$TW_VERSION"; exit 0 ;;
      --selftest)    selftest; exit $? ;;
      --caveats)     caveats; exit 0 ;;
      --profile)     need_arg "$@"; collect_profile "$2"; shift 2; set -- "${PROFILE_TOKENS[@]}" "$@" ;;

      # --- filesystem view ---------------------------------------------
      --bind)        need_arg "$@"; USER_BINDS+=("$(expand_path "$2")"); shift 2 ;;
      --ro-bind)     need_arg "$@"; USER_RBINDS+=("$(expand_path "$2")"); shift 2 ;;
      --dev-bind)    need_arg "$@"; USER_DEVB+=("$(expand_path "$2")"); shift 2 ;;
      --hide|--deny) need_arg "$@"; HIDES+=("$(expand_path "$2")"); shift 2 ;;
      --tmpfs)       need_arg "$@"; TMPFS_PATHS+=("$(expand_path "$2")"); shift 2 ;;
      --rootfs)      need_arg "$@"; ROOTFS="$(expand_path "$2")"; [[ -d $ROOTFS ]] || die "rootfs not found: $ROOTFS"; shift 2 ;;
      --workdir|-w)  need_arg "$@"; GCWD="$2"; shift 2 ;;

      # --- sandbox identity / lifecycle --------------------------------
      --home)        need_arg "$@"; valid_name "$2"; BOX_NAME="$2"; shift 2 ;;
      --ephemeral)   EPHEMERAL=1; shift ;;
      --jail)        need_arg "$@"; valid_name "$2"; JAIL="$2"; shift 2 ;;
      --ephemeral-jail) EPHEMERAL_JAIL=1; shift ;;
      --label)       need_arg "$@"; SANDBOX_LABEL="$2"; shift 2 ;;
      --script)      need_arg "$@"; SCRIPT_FILE="$(expand_path "$2")"; [[ -f $SCRIPT_FILE ]] || die "script not found: $SCRIPT_FILE"; shift 2 ;;
      --allow-nested) ALLOW_NESTED=1; shift ;;

      # --- environment ---------------------------------------------------
      --clearenv)    CLEARENV=1; shift ;;
      --setenv)      need_arg "$@"; [[ "$2" == *=* ]] || die "--setenv expects K=V"; ENVS+=("$2"); shift 2 ;;
      --unsetenv)    need_arg "$@"; UNSETS+=("$2"); shift 2 ;;

      # --- transport / resources -----------------------------------------
      --unshare-net|--no-net) NETBLOCK=1; shift ;;
      --timeout)     need_arg "$@"; [[ "$2" =~ ^[0-9]+$ ]] || die "--timeout expects seconds"; TIMEOUT="$2"; shift 2 ;;
      --max-procs)   need_arg "$@"; LIM_PROCS="$2"; shift 2 ;;
      --max-files)   need_arg "$@"; LIM_FILES="$2"; shift 2 ;;
      --max-fsize)   need_arg "$@"; LIM_FSIZE="$2"; shift 2 ;;   # MB
      --max-mem)     need_arg "$@"; LIM_MEM="$2"; shift 2 ;;     # MB (addr space)
      --nice)        need_arg "$@"; NICE_L="$2"; shift 2 ;;

      # --- observability ---------------------------------------------------
      --audit)       need_arg "$@"; AUDIT="$2"; shift 2 ;;
      --dry-run)     DRY_RUN=1; shift ;;
      --quiet|-q)    QUIET=1; shift ;;

      # --- tmp policy -------------------------------------------------------
      --fresh-tmp)   FRESH_TMP=1; shift ;;
      --share-tmp)   FRESH_TMP=0; shift ;;

      # --- root faking -------------------------------------------------------
      -0|--fakeroot)    FAKE_ROOT=1; shift ;;
      --no-fakeroot)    FAKE_ROOT=0; shift ;;

      --*) die "unknown flag: $1  (tw --help)" ;;
      *)   CMD=("$@"); return 0 ;;
    esac
  done
}

# --------------------------------------------------------------------------
# jail management:  tw jail <build|rebuild|discard|list|path> [NAME]
# --------------------------------------------------------------------------
jail_build() {
  local name="$1" force="${2:-0}" dir; valid_name "$name"; dir="$(jail_dir "$name")"
  [[ -d "$dir" ]] && [[ "$force" != 1 ]] && die "jail '$name' exists (use: tw jail rebuild $name)"
  rm -rf "$dir"; mkdir -p "$dir"
  say "building jail ${C_GRN}$name${C_RST} — snapshotting \$PREFIX (this can take a minute)…"
  local t0=$SECONDS
  ( cd "$PREFIX" && tar -cf - \
      --exclude='./tmp' --exclude='./var/cache' --exclude='./var/log' . 2>/dev/null ) \
    | ( cd "$dir" && tar -xf - ) \
    || die "snapshot failed (need: tar; check disk space)"
  mkdir -p "$dir/tmp"
  {
    printf 'name=%s\ncreated=%s\ntw=%s\n' "$name" "$(date -Is)" "$TW_VERSION"
    du -sh "$dir" 2>/dev/null | awk '{printf "size=%s\n",$1}'
  } > "$dir/.tw-jail"
  ok "jail '$name' ready ($(du -sh "$dir" 2>/dev/null | cut -f1)) in $((SECONDS-t0))s → $dir"
}

tw_jail() {
  local op="${1:-}" name="${2:-stock}"
  case "$op" in
    build)   jail_build "$name" 0 ;;
    rebuild) jail_build "$name" 1 ;;
    discard) valid_name "$name"; rm -rf "$(jail_dir "$name")" && ok "jail '$name' discarded" ;;
    path)    valid_name "$name"; jail_dir "$name"; echo ;;
    list)
      printf '%s%-16s %-8s %s%s\n' "$C_DIM" "NAME" "SIZE" "PATH" "$C_RST"
      local d b
      for d in "$TW_HOME/jails"/*; do
        [[ -d $d ]] || continue; b="${d##*/}"
        printf '%-16s %-8s %s\n' "$b" "$(du -sh "$d" 2>/dev/null | cut -f1)" "$d"
      done ;;
    *) die "usage: tw jail <build|rebuild|discard|list|path> [name]" ;;
  esac
  exit 0
}

# --------------------------------------------------------------------------
# diagnostics
# --------------------------------------------------------------------------
usage() {
cat <<'EOF'
  termwrap (tw) — ptrace sandbox for unrooted Termux · v0.1.0

  USAGE
    tw [FLAGS] [--] CMD [ARGS...]        run CMD inside the sandbox
    tw [FLAGS]                           interactive shell if no CMD
    tw jail <build|rebuild|discard|list|path> [NAME]
    tw --selftest | --caveats

  FILESYSTEM VIEW
    --bind SRC[:DST]      bind SRC rw into the guest        (bwrap: --bind)
    --ro-bind SRC[:DST]   bind read-only  (chmod snapshot; best-effort)
    --dev-bind SRC[:DST]  bind device nodes                 (bwrap: --dev-bind)
    --hide PATH           PATH does not exist for the guest (empty overlay)
    --tmpfs PATH          empty writable overlay at PATH
    --rootfs DIR          use DIR as / (advanced proot -r)
    -w, --workdir DIR     start in DIR (default: sandbox $HOME)

  IDENTITY / LIFECYCLE
    --home NAME           persistent named home (default: "default")
    --ephemeral           fresh $HOME per run, wiped on exit
    --jail NAME           bind tar-snapshot jail over $PREFIX (rm-proof)
    --ephemeral-jail      copy jail per run, discard at exit
    --script FILE         bind host FILE into the guest and execute it
    --allow-nested        permit tw inside tw (refused by default)

  ENVIRONMENT
    --clearenv            scrub env; keep only HOME/PATH/TERM/TMPDIR/PREFIX
    --setenv K=V          inject variable          --unsetenv K   drop one

  TRANSPORT / RESOURCES
    --unshare-net         fail-closed network via LD_PRELOAD socket shim
    --timeout SECONDS     hard-kill the whole tree after N seconds
    --max-procs N         ulimit -u        --max-files N   ulimit -n
    --max-fsize MB        ulimit -f        --max-mem MB    ulimit -v
    --nice N              scheduling niceness 0..19

  OBSERVABILITY
    --audit FILE          proot -v9 systrace → FILE (non-absolute → TW logs dir)
    --dry-run             print the exact proot command, change nothing
    -q, --quiet           suppress termwrap banners

  TMP POLICY / ROOT FAKING
    --fresh-tmp           empty overlay on $PREFIX/tmp (default)
    --share-tmp           expose real $PREFIX/tmp
    -0, --fakeroot        fake uid 0 (default)    --no-fakeroot   real uid

  STATE         $TW_HOME   (homes, jails, logs, tmp, profiles.d)
  PROFILES      flag-files, one flag per line, '#'-comments,
                searched in  $TW_HOME/profiles.d  then  $PREFIX/share/termwrap/profiles
EOF
}

caveats() {
cat <<'EOF'
  HONEST LIMITATIONS — read before trusting a run

  1. SAME-UID CEILING   proot rewrites paths, not capabilities. The guest
     keeps your Termux uid; a hostile native binary that ignores the
     filesystem (or knows ptrace tricks) can poke you. Use Android Work
     Profiles (Shelter/Insular) for a real uid split around whole sessions.
  2. NETBLOCK SCOPE     --unshare-net is an LD_PRELOAD shim over libc
     socket(): fail-closed for Termux packages (python, node, curl, wget).
     Static binaries and Go's raw-syscall dial path BYPASS it. Treat as an
     agent-safety rail, not a netns.
  3. RO-BIND            enforced by chmod a-w snapshot + restore on exit.
     Best-effort: crash windows and already-open fds are not covered.
  4. PTRACE OVERHEAD    fork/exec-heavy workloads pay 1.5–3×.
     For compute jobs without side-effects, run them unsandboxed.
  5. NO PID/NS ISOLATION the guest sees your process table and can signal
     within uid. No true unshare. It's a cage of view, not of privilege.
  6. THE POINT          for AI agents the winning combo is:
        tw --profile ai-agent --jail stock --timeout 900 -- <agent>
     jail = destructive ops hit a tar snapshot, never your real $PREFIX;
     netblock = no exfiltration through libc sockets; audit = every exec.
  Android 12+ tip: kill the phantom-process monitor or proots get culled:
        adb shell settings put global settings_enable_monitor_phantom_procs false
EOF
}

selftest() {
  local pass=0 fail=0 t
  _p() { t="$1"; pass=$((pass+1)); ok "selftest: $t"; }
  _f() { t="$1"; fail=$((fail+1)); err "selftest: $t"; }
  [[ "$PREFIX" == *com.termux* ]] && _p "termux environment ($PREFIX)" || _f "not a termux env"
  if command -v proot >/dev/null; then _p "proot present ($(proot --version 2>/dev/null | head -n1))"
  else _f "proot missing → pkg install proot"; fi
  if proot -0 --kill-on-exit -b /dev -b /proc "$PREFIX/bin/true" 2>/dev/null \
     || proot -0 --kill-on-exit -b /dev -b /proc /system/bin/true 2>/dev/null; then
    _p "proot exec smoke"; else _f "proot exec smoke"; fi
  for b in tar timeout env od awk; do
    command -v "$b" >/dev/null && _p "tool: $b" || _f "tool missing: $b"
  done
  if [[ -f "$NETBLOCK_SO" ]]; then
    _p "netblock shim present"
    if TW_NETBLOCK=1 LD_PRELOAD="$NETBLOCK_SO" bash -c 'exec 3<>/dev/tcp/127.0.0.1/9' 2>/dev/null
    then _f "netblock did NOT fail closed"; else _p "netblock fails closed (EACCES)"; fi
  else warn "selftest[skip]: netblock shim not built ($NETBLOCK_SO)"; fi
  mkdir -p "$TW_HOME"/{home,jails,logs,tmp,profiles.d} 2>/dev/null \
    && _p "state dir writable ($TW_HOME)" || _f "state dir not writable"
  say "selftest: ${C_GRN}${pass} ok${C_RST} · ${C_RED}${fail} fail${C_RST}"
  [[ $fail -eq 0 ]]
}

# --------------------------------------------------------------------------
# cleanup
# --------------------------------------------------------------------------
cleanup() {
  local rc=$?
  [[ -n "${CHILD_PID:-}" ]] && kill -0 "$CHILD_PID" 2>/dev/null && kill "$CHILD_PID" 2>/dev/null
  local p
  for p in "${CLEAN_RO[@]:-}";     do [[ -n $p && -e $p ]] && chmod -R u+w -- "$p" 2>/dev/null; done
  for p in "${CLEAN_TMPDIRS[@]:-}";do [[ -n $p && -d $p ]] && rm -rf -- "$p" 2>/dev/null; done
  [[ -n "$CLEAN_EPH_HOME" && -d "$CLEAN_EPH_HOME" ]] && rm -rf -- "$CLEAN_EPH_HOME" 2>/dev/null
  return $rc
}
on_sig() { say "signal caught — killing sandbox tree"; [[ -n ${CHILD_PID:-} ]] && kill -- "$CHILD_PID" 2>/dev/null; }
trap cleanup EXIT
trap on_sig INT TERM

# ==========================================================================
# MAIN
# ==========================================================================
[[ "${1:-}" == "jail" ]] && { mkdir -p "$TW_HOME"/{jails,home,logs,tmp}; shift; tw_jail "$@"; }

mkdir -p "$TW_HOME"/{home,jails,logs,tmp,profiles.d}

# early quiet pre-scan: -q must silence profile banners even when --profile
# appears before -q on the command line
for _a in "$@"; do
  [[ "$_a" == "-q" || "$_a" == "--quiet" ]] && QUIET=1
done
unset _a

parse_args "$@"

# nested-run guard: agents love to re-sandbox; refuse by default
if [[ -n "${TW_SANDBOX_ID:-}" && $ALLOW_NESTED != 1 && "${TW_ALLOW_NESTED:-0}" != 1 ]]; then
  die "already inside sandbox ${TW_SANDBOX_ID} (use --allow-nested, or TW_ALLOW_NESTED=1)"
fi

# --- identity ---------------------------------------------------------------
local_id="$(rand_id)"
[[ -n "$SANDBOX_LABEL" ]] && SID="$SANDBOX_LABEL" || SID="${local_id:-tw0}"
[[ "$EPHEMERAL" == 0 && "$BOX_NAME" != "default" ]] && SID="$BOX_NAME"

# --- sandbox home -------------------------------------------------------------
if [[ "$EPHEMERAL" == 1 ]]; then
  BOX_HOME="$(mktemp -d "$TW_HOME/tmp/home-$SID.XXXXXX")" || die "cannot create ephemeral home"
  CLEAN_EPH_HOME="$BOX_HOME"
else
  BOX_HOME="$TW_HOME/home/$BOX_NAME"; mkdir -p "$BOX_HOME"
fi

# provision rc + notice (idempotent: don't clobber user edits)
[[ -f "$BOX_HOME/.bashrc" ]] || cat > "$BOX_HOME/.bashrc" <<'EOF'
# termwrap sandbox rc
PS1='[tw:${TW_SANDBOX_ID:0:6}] \w \$ '
alias tw-help='cat "$HOME/.sandbox-notice"'
EOF
[[ -f "$BOX_HOME/.bash_profile" ]] || printf '[ -f ~/.bashrc ] && . ~/.bashrc\n' > "$BOX_HOME/.bash_profile"
cat > "$BOX_HOME/.sandbox-notice" <<EOF
this is a termwrap sandbox.
  id        $SID
  mode      $([[ $EPHEMERAL == 1 ]] && echo ephemeral || echo "persistent ($BOX_NAME)")
  jail      ${JAIL:-none}   net: $([[ $NETBLOCK == 1 ]] && echo BLOCKED || echo allowed)
  mounted   $(date -Is)
your real \$HOME is shadowed; what you see as ~ lives at $BOX_HOME
EOF

# --- jail binding ---------------------------------------------------------------
JAIL_BIND_SRC=""
if [[ -n "$JAIL" ]]; then
  local_j="$(jail_dir "$JAIL")"
  [[ -d "$local_j" && -f "$local_j/.tw-jail" ]] || die "jail '$JAIL' missing — build it: tw jail build $JAIL"
  if [[ "$EPHEMERAL_JAIL" == 1 ]]; then
    say "cloning jail '$JAIL' for single run (cp -a)…"
    run_j="$(mktemp -d "$TW_HOME/tmp/jail-$SID.XXXXXX")"
    cp -a "$local_j/." "$run_j/" || die "jail clone failed"
    CLEAN_TMPDIRS+=("$run_j")       # wipe the sacrificial copy at exit
    local_j="$run_j"
  fi
  JAIL_BIND_SRC="$local_j"
fi

# --- read-only snapshot: chmod a-w, restore in cleanup -------------------------
for spec in "${USER_RBINDS[@]:-}"; do
  [[ -z "$spec" ]] && continue
  src="${spec%%:*}"
  [[ -e "$src" ]] || die "--ro-bind source missing: $src"
  if chmod -R a-w -- "$src" 2>/dev/null; then
    CLEAN_RO+=("$src"); [[ $QUIET == 0 ]] && ok "ro-bind: ${C_DIM}$src${C_RST} (a-w snapshot)"
  else
    warn "ro-bind: could not chmod $src — NOT write-protected"
  fi
done

# --- assemble proot arguments ---------------------------------------------------
PARGS=(--kill-on-exit --link2symlink)
[[ $FAKE_ROOT == 1 ]] && PARGS+=(-0)
[[ -n "$AUDIT" ]]    && PARGS+=(-v "$PROOT_V")
[[ -n "$ROOTFS" ]]   && PARGS+=(-r "$ROOTFS")
[[ -z "$ROOTFS" ]]   && PARGS+=(-b /dev -b /proc -b /sys)
# jail first so user binds/tmpfs can stack on top
[[ -n "$JAIL_BIND_SRC" ]] && PARGS+=(-b "$JAIL_BIND_SRC:$PREFIX")
# shadow the real $HOME with the sandbox home (this is the isolation)
PARGS+=(-b "$BOX_HOME:$HOME")
# fresh /tmp overlay
if [[ $FRESH_TMP == 1 ]]; then
  tmp_overlay="$(mktmpdir)"; PARGS+=(-b "$tmp_overlay:$PREFIX/tmp")
fi
# tmpfs overlays requested by the user
for tp in "${TMPFS_PATHS[@]:-}"; do
  [[ -z "$tp" ]] && continue
  d="$(mktmpdir)"; PARGS+=(-b "$d:$tp"); [[ $QUIET == 0 ]] && ok "tmpfs: ${C_DIM}$tp${C_RST}"
done
# hides
EMPTY_HIDE=""
for hp in "${HIDES[@]:-}"; do
  [[ -z "$hp" ]] && continue
  if [[ -d "$hp" || "$hp" == */ ]]; then
    [[ -z "$EMPTY_HIDE" ]] && EMPTY_HIDE="$(mktmpdir)"
    PARGS+=(-b "$EMPTY_HIDE:$hp")
  else
    PARGS+=(-b /dev/null:"$hp")
  fi
  [[ $QUIET == 0 ]] && ok "hidden: ${C_DIM}$hp${C_RST}"
done
# user binds
for spec in "${USER_BINDS[@]:-}" "${USER_DEVB[@]:-}" "${USER_RBINDS[@]:-}"; do
  [[ -z "$spec" ]] && continue
  if [[ "$spec" == *:* ]]; then src="${spec%%:*}"; dst="${spec#*:}"
  else src="$spec"; dst="$spec"; fi
  [[ -e "$src" ]] || die "--bind source missing: $src"
  PARGS+=(-b "$src:$dst")
done

# --- guest working dir -----------------------------------------------------------
[[ -z "$GCWD" ]] && GCWD="$HOME"

# --- command ---------------------------------------------------------------------
if [[ -n "$SCRIPT_FILE" && ${#CMD[@]} -eq 0 ]]; then
  cp -f "$SCRIPT_FILE" "$BOX_HOME/.tw-entry" 2>/dev/null || die "cannot stage $SCRIPT_FILE"
  chmod +x "$BOX_HOME/.tw-entry" 2>/dev/null
  CMD=("bash" "-l" "$HOME/.tw-entry")
fi
[[ ${#CMD[@]} -eq 0 ]] && CMD=("bash" "-l")

# --- environment -------------------------------------------------------------------
EOPTS=()
if [[ $CLEARENV == 1 ]]; then
  EOPTS=(-i
    "HOME=$HOME" "PREFIX=$PREFIX" "TMPDIR=$PREFIX/tmp"
    "PATH=$PREFIX/bin:$PREFIX/bin/applets:/system/bin:/system/xbin"
    "TERM=${TERM:-xterm-256color}" "LANG=${LANG:-en_US.UTF-8}")
else
  for k in "${UNSETS[@]:-}"; do [[ -n $k ]] && EOPTS+=(-u "$k"); done
fi
EOPTS+=("TW_SANDBOX_ID=$SID" "TW_HOME=$TW_HOME")
[[ $NETBLOCK == 1 ]] && EOPTS+=("TW_NETBLOCK=1" "LD_PRELOAD=$NETBLOCK_SO")
# log blocked socket attempts into the audit stream when auditing
[[ $NETBLOCK == 1 && -n "$AUDIT" ]] && EOPTS+=("TW_NETBLOCK_LOG=1")
for kv in "${ENVS[@]:-}"; do [[ -n $kv ]] && EOPTS+=("$kv"); done

# --- resource cage (runs as a bash preamble inside proot) --------------------------
PRE="ulimit -Sc 0 2>/dev/null; "
[[ -n "$LIM_FILES" ]] && PRE+="ulimit -n $LIM_FILES 2>/dev/null; "
[[ -n "$LIM_PROCS" ]] && PRE+="ulimit -u $LIM_PROCS 2>/dev/null; "
[[ -n "$LIM_FSIZE" ]] && PRE+="ulimit -f $(( LIM_FSIZE * 1024 )) 2>/dev/null; "
[[ -n "$LIM_MEM" ]]   && PRE+="ulimit -v $(( LIM_MEM * 1024 )) 2>/dev/null; "

INNER=( env "${EOPTS[@]}" bash -c "${PRE}exec \"\$@\"" "tw-sh" "${CMD[@]}" )

FULL=( proot "${PARGS[@]}" -w "$GCWD" "${INNER[@]}" )
[[ "$NICE_L" != 0 ]] && FULL=( nice -n "$NICE_L" "${FULL[@]}" )
[[ "$TIMEOUT" != 0 ]] && FULL=( timeout -k 3 -s KILL "$TIMEOUT" "${FULL[@]}" )

# --- dry run -----------------------------------------------------------------------
if [[ $DRY_RUN == 1 ]]; then
  say "dry-run — nothing executed"
  printf '%s' "$C_DIM"
  printf '  %q' "${FULL[@]}" | fold -s -w 100 | sed 's/^/  /'
  printf '%s\n' "$C_RST"
  exit 0
fi

# --- netblock sanity ------------------------------------------------------------------
if [[ $NETBLOCK == 1 && ! -f "$NETBLOCK_SO" ]]; then
  die "netblock shim missing — run the installer (builds $NETBLOCK_SO)"
fi

# --- banner -----------------------------------------------------------------------------
[[ $QUIET == 0 ]] && {
  printf '%s┌─ termwrap %s ── sid %s%s%s\n' "$C_DIM" "$TW_VERSION" "$C_GRN" "$SID" "$C_RST" >&2
  printf '%s│%s home %s %s\n' "$C_DIM" "$C_RST" "$([[ $EPHEMERAL == 1 ]] && echo "(ephemeral)" || echo "(persist:$BOX_NAME)")" "$BOX_HOME" >&2
  [[ -n $JAIL ]]      && printf '%s│%s jail %s → /usr overlay\n' "$C_DIM" "$C_RST" "$JAIL" >&2
  [[ $NETBLOCK == 1 ]] && printf '%s│%s net  %sBLOCKED%s (LD_PRELOAD shim)\n' "$C_DIM" "$C_RST" "$C_RED" "$C_RST" >&2
  [[ $TIMEOUT != 0 ]]  && printf '%s│%s fuse %ss hard-kill\n' "$C_DIM" "$C_RST" "$TIMEOUT" >&2
  printf '%s└─%s exec %q' "$C_DIM" "$C_RST" "${CMD[0]}" >&2
  (( ${#CMD[@]} > 1 )) && printf ' %q' "${CMD[@]:1}" >&2
  printf '\n' >&2
}

# --- audit plumbing ----------------------------------------------------------------------
AUDIT_FILE=""
if [[ -n "$AUDIT" ]]; then
  AUDIT_FILE="$AUDIT"; [[ "$AUDIT_FILE" != /* ]] && AUDIT_FILE="$TW_HOME/logs/$AUDIT_FILE"
fi

# --- launch -------------------------------------------------------------------------------
T0=$(date +%s)
if [[ -n "$AUDIT_FILE" ]]; then
  "${FULL[@]}" 2> "$AUDIT_FILE" & CHILD_PID=$!
else
  "${FULL[@]}" & CHILD_PID=$!
fi
wait "$CHILD_PID"; RC=$?
CHILD_PID=""
T1=$(date +%s)

# --- epilogue -----------------------------------------------------------------------------
if [[ -n "$AUDIT_FILE" ]]; then
  nx=$(awk '/execve/{n++} END{print n+0}' "$AUDIT_FILE" 2>/dev/null)
  nb=$(awk '/tw-net/{n++} END{print n+0}'  "$AUDIT_FILE" 2>/dev/null)
  [[ $QUIET == 0 ]] && say "audit → ${C_DIM}$AUDIT_FILE${C_RST}  (${nx:-0} execve · ${nb:-0} netblocks)"
fi
if [[ $TIMEOUT != 0 && $RC -ge 124 && $RC -le 137 ]]; then
  warn "fuse blown: sandbox hard-killed after ${TIMEOUT}s"
fi
if [[ $QUIET == 0 ]]; then
  emo="[ok]"; [[ $RC != 0 ]] && emo="[x]"
  printf '%s%s%s sandbox %s torn down · %ss · exit %d · host untouched\n' \
    "${C_DIM}" "$emo" "${C_RST}" "$SID" "$((T1-T0))" "$RC" >&2
fi
exit "$RC"

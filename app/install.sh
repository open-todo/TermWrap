#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  termwrap installer — single-file bootstrap for Termux (unrooted Android)
#
#  curl -fsSL <this-site>/files/install.sh | bash
#
#  What it does:
#    1. installs deps: proot coreutils tar findutils clang
#    2. installs tw        -> $PREFIX/bin/tw
#    3. builds netblock.so -> $PREFIX/lib/termwrap/netblock.so
#    4. installs profiles  -> $PREFIX/share/termwrap/profiles/
#    5. runs tw --selftest
#  Idempotent. Re-run to upgrade.
#
#  COPYRIGHT OPENTODO© — released under the MIT license.
# =============================================================================
set -euo pipefail

if [[ -t 1 ]]; then
  G=$'\033[38;5;114m'; C=$'\033[38;5;81m'; R=$'\033[38;5;203m'
  A=$'\033[38;5;215m'; D=$'\033[2m';        Z=$'\033[0m'
else G=""; C=""; R=""; A=""; D=""; Z=""; fi
say() { printf '%s::%s %s\n'  "$C" "$Z" "$*"; }
ok()  { printf '%s[ok]%s %s\n' "$G" "$Z" "$*"; }
warn(){ printf '%s[!]%s  %s\n' "$A" "$Z" "$*"; }
die() { printf '%s[x]%s  %s\n' "$R" "$Z" "$*" >&2; exit 1; }

printf '%s' "$C"
cat <<'BANNER'
        __
      _|  |_
     |  ___  |    termwrap  ·  ptrace sandbox for unrooted android
     | |   | |_     tw v0.2.0 — no root, no namespaces, no excuses
     | |___  __|
     |_______|
BANNER
printf '%s' "$Z"

# --- 0. environment checks --------------------------------------------------
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
[[ "$PREFIX" == *com.termux* && -d "$PREFIX/bin" ]] \
  || die "this installer must run inside Termux (found PREFIX=$PREFIX)"
command -v pkg >/dev/null || die "'pkg' not found — are you inside Termux?"

TW_HOME="${TW_HOME:-$HOME/.local/share/termwrap}"
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/termwrap"
PROFILE_DIR="$PREFIX/share/termwrap/profiles"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# --- 1. dependencies ----------------------------------------------------------
say "installing dependencies (proot coreutils tar findutils clang util-linux)…"
pkg install -y proot coreutils tar findutils clang util-linux >/dev/null \
  || die "pkg install failed — check your repos/network, then re-run"
ok "dependencies ready"

# --- 2. tw binary (prefer sibling file, else embedded payload) ----------------
if [[ -f "$PWD/termwrap.sh" ]]; then
  say "using local ./termwrap.sh"
  install -m 0755 "$PWD/termwrap.sh" "$BIN_DIR/tw"
else
  say "writing $BIN_DIR/tw (embedded payload)"
  cat > "$BIN_DIR/tw" <<'__TW_PAYLOAD_SCRIPT__'
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
#  v0.2.0 hardening:
#   - sandbox runs in its own process group (setsid) so teardown can TERM
#     then KILL the whole tree — no more orphans after --timeout/signals
#   - --ro-bind is refused under fakeroot (-0): proot's fake_id0 would lift
#     file modes for the guest, silently defeating write protection
#   - ro-bind mode restore is exact (was: lossy u+w only)
#   - --unshare-net env applied AFTER user env; user LD_PRELOAD /
#     TW_NETBLOCK injection refused (netblock cannot be env-disarmed)
#   - --dry-run performs no persistent state changes
#   - profile parser: sequential --profile works; stray tokens fail loudly
#   - resource limits validated; silent ulimit failures are reported
#
#  COPYRIGHT OPENTODO© — released under the MIT license.
# =============================================================================

set -uo pipefail

readonly TW_VERSION="0.2.0"
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
EPHEMERAL_EXPLICIT=0    # --ephemeral given explicitly (precedence warnings)
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
RO_MODES=()              # per-ro-bind mode snapshots (exact restore)
CLEAN_EPH_HOME=""
CHILD_PID=""
FUSE_PID=""
TREE_ALIVE=0

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
need_arg() { [[ $# -ge 2 && -n ${2:-} ]] || die "flag $1 needs an argument"; }

num_arg() { [[ "${2:-}" =~ ^[0-9]+$ ]] || die "$1 expects a non-negative integer (got '${2:-}')"; }

bind_arity_warn() {  # guard against bwrap-style two-arg usage: --bind SRC DST
  [[ "$2" == *:* || -z "$3" || "$3" == -* ]] && return 0
  warn "bwrap-style two-arg '$1 $2 $3' detected — '$3' would run as the command."
  warn "  termwrap syntax is '$1 SRC:DST'; put '--' before the command to disambiguate."
}

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
# Fully expands --profile includes at load time (depth-limited, recursion-
# safe), validates tokens: one flag per line, values inline, '#'-comments.
# A stray bare token would otherwise silently become the guest command.
# --------------------------------------------------------------------------
PROFILE_TOKENS=()
collect_profile() {
  local q="$1" depth="${2:-0}" f=""
  if   [[ -f "$q" ]];                       then f="$q"
  elif [[ -f "$TW_PROFILES_USR/$q.conf" ]]; then f="$TW_PROFILES_USR/$q.conf"
  elif [[ -f "$TW_PROFILES_USR/$q" ]];      then f="$TW_PROFILES_USR/$q"
  elif [[ -f "$TW_PROFILES_SYS/$q.conf" ]]; then f="$TW_PROFILES_SYS/$q.conf"
  elif [[ -f "$TW_PROFILES_SYS/$q" ]];      then f="$TW_PROFILES_SYS/$q"
  else die "profile not found: $q (looked in $TW_PROFILES_USR and $TW_PROFILES_SYS)"
  fi
  [[ $depth -gt 4 ]] && die "profile recursion too deep ($q)"
  local line tok i prev=0
  local -a toks=()
  # flags that legitimately take a following value token on the same line
  local VALFLAGS="--bind --ro-bind --dev-bind --hide --deny --tmpfs --rootfs
                  -w --workdir --home --jail --label --script --setenv
                  --unsetenv --timeout --max-procs --max-files --max-fsize
                  --max-mem --nice --audit"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                      # strip comments
    [[ -z "${line//[[:space:]]/}" ]] && continue
    # shellcheck disable=SC2206
    toks=($line)                             # intentional word-split (one flag per line)
    for tok in "${toks[@]}"; do
      if [[ $prev == 1 ]]; then prev=0       # this token is a flag's value
      elif [[ "$tok" == --profile ]]; then
        :                                    # handled below via index walk
      elif [[ "$tok" != -* ]]; then
        die "profile '$q': stray token '$tok' — profiles accept flags only (values inline, e.g. --setenv K=V)"
      fi
      [[ " $VALFLAGS " == *" $tok "* ]] && prev=1
    done
    # walk tokens so nested --profile includes expand recursively
    i=0
    while [[ $i -lt ${#toks[@]} ]]; do
      tok="${toks[$i]}"
      if [[ "$tok" == --profile ]]; then
        i=$((i+1))
        [[ $i -lt ${#toks[@]} ]] || die "profile '$q': --profile needs a name"
        collect_profile "${toks[$i]}" "$((depth+1))"
      else
        PROFILE_TOKENS+=("$tok")
      fi
      i=$((i+1))
    done
  done < "$f"
  [[ $QUIET == 0 && $depth == 0 ]] && say "profile ${C_GRN}${q}${C_RST} ← ${C_DIM}$f${C_RST} (${#PROFILE_TOKENS[@]} flags)"
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
      --bind)        need_arg "$@"; bind_arity_warn "$1" "$2" "${3:-}"; USER_BINDS+=("$(expand_path "$2")"); shift 2 ;;
      --ro-bind)     need_arg "$@"; bind_arity_warn "$1" "$2" "${3:-}"; USER_RBINDS+=("$(expand_path "$2")"); shift 2 ;;
      --dev-bind)    need_arg "$@"; bind_arity_warn "$1" "$2" "${3:-}"; USER_DEVB+=("$(expand_path "$2")"); shift 2 ;;
      --hide|--deny) need_arg "$@"; HIDES+=("$(expand_path "$2")"); shift 2 ;;
      --tmpfs)       need_arg "$@"; TMPFS_PATHS+=("$(expand_path "$2")"); shift 2 ;;
      --rootfs)      need_arg "$@"; ROOTFS="$(expand_path "$2")"; [[ -d $ROOTFS ]] || die "rootfs not found: $ROOTFS"; shift 2 ;;
      --workdir|-w)  need_arg "$@"; GCWD="$2"; shift 2 ;;

      # --- identity / lifecycle --------------------------------
      --home)        need_arg "$@"; valid_name "$2"; BOX_NAME="$2"; shift 2 ;;
      --ephemeral)   EPHEMERAL=1; EPHEMERAL_EXPLICIT=1; shift ;;
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
      --timeout)     need_arg "$@"; num_arg "$1" "$2"; TIMEOUT="$2"; shift 2 ;;
      --max-procs)   need_arg "$@"; num_arg "$1" "$2"; LIM_PROCS="$2"; shift 2 ;;
      --max-files)   need_arg "$@"; num_arg "$1" "$2"; LIM_FILES="$2"; shift 2 ;;
      --max-fsize)   need_arg "$@"; num_arg "$1" "$2"; LIM_FSIZE="$2"; shift 2 ;;   # MB
      --max-mem)     need_arg "$@"; num_arg "$1" "$2"; LIM_MEM="$2"; shift 2 ;;     # MB (addr space)
      --nice)        need_arg "$@"; num_arg "$1" "$2"; [[ $2 -le 19 ]] || die "--nice range is 0..19"; NICE_L="$2"; shift 2 ;;

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
  termwrap (tw) — ptrace sandbox for unrooted Termux · v0.2.0

  USAGE
    tw [FLAGS] [--] CMD [ARGS...]        run CMD inside the sandbox
    tw [FLAGS]                           interactive shell if no CMD
    tw jail <build|rebuild|discard|list|path> [NAME]
    tw --selftest | --caveats

  FILESYSTEM VIEW
    --bind SRC[:DST]      bind SRC rw into the guest        (bwrap: --bind)
    --ro-bind SRC[:DST]   bind read-only. Enforced ONLY with --no-fakeroot;
                          refused under the default -0 (proot fake_id0 lifts
                          file modes for the guest — TW_ALLOW_ROBIND_FAKE=1
                          overrides the refusal). Modes restored exactly.
    --dev-bind SRC[:DST]  bind device nodes                 (bwrap: --dev-bind)
    --hide PATH           shadow PATH: dirs appear empty, files read as /dev/null
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
    --audit FILE          proot -v9 systrace → FILE (non-absolute → TW logs dir).
                          NOTE: while auditing, guest stderr goes into FILE too.
    --dry-run             print the exact proot command; no persistent changes
    -q, --quiet           suppress termwrap banners

  TMP POLICY / ROOT FAKING
    --fresh-tmp           empty overlay on $PREFIX/tmp (default)
    --share-tmp           expose real $PREFIX/tmp
    -0, --fakeroot        fake uid 0 (default)    --no-fakeroot   real uid

  STATE         $TW_HOME   (homes, jails, logs, tmp, profiles.d)
  PROFILES      flag-files, one flag per line, '#'-comments, values inline
                (e.g. --setenv K=V), searched in  $TW_HOME/profiles.d  then
                $PREFIX/share/termwrap/profiles; --profile includes allowed
  SAFETY ENVS   TW_ALLOW_NESTED · TW_ALLOW_ROBIND_FAKE · TW_NETBLOCK_SO
                TW_DEBUG · NO_COLOR
  TEARDOWN      the sandbox runs in its own process group (setsid); on
                timeout/exit/signal tw TERMs then KILLs the whole tree and
                verifies it is gone before reporting success
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
     Static binaries and Go's raw-syscall dial path BYPASS it — and so can
     the guest itself with one builtin: `unset LD_PRELOAD` or
     `env -u LD_PRELOAD`. It stops network ACCIDENTS (hallucinated curl,
     injected fetches by naive code), not a process that knows it is boxed.
     tw refuses user --setenv/--unsetenv of LD_PRELOAD/TW_NETBLOCK, but the
     guest can still edit its own env at runtime. Real egress control for
     sandbox-aware agents = keep the network on the HOST side of the loop.
  3. RO-BIND            Enforced by chmod a-w snapshot + exact mode restore.
     Refused under the default -0 fakeroot: proot's fake_id0 extension
     really chmods host files writable for a fake-root guest, silently
     defeating chmod-based protection (use --no-fakeroot, or --hide —
     absence beats permissions). Even with --no-fakeroot, crash windows
     and already-open fds are not covered.
  4. PTRACE OVERHEAD    fork/exec-heavy workloads pay 1.5–3×.
     For compute jobs without side-effects, run them unsandboxed.
  5. NO PID/NS ISOLATION the guest sees your process table and can signal
     within uid. No true unshare. It's a cage of view, not of privilege.
  6. TEARDOWN EDGES     since 0.2.0 the sandbox tree runs in its own process
     group and tw TERMs→KILLs it on timeout/exit/signal, verifying death.
     Residual risk: a tracer killed before cleanup (OOM, adb kill) cannot
     restore ro-bind modes; always prefer --hide for precious paths.
  7. THE POINT          for AI agents the winning combo is:
        tw --profile ai-agent --jail stock --timeout 900 -- <agent>
     jail = destructive ops hit a tar snapshot, never your real $PREFIX;
     netblock = no accidental exfiltration through libc sockets; audit =
     every exec. Pair with the agent-guard two-phase loop: model proposes
     on the HOST (network side), sandbox disposes on the action side.
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
  # 1. guarantee the sandbox PROCESS GROUP is dead (tracer + every tracee)
  if [[ -n "${CHILD_PID:-}" ]]; then
    kill -KILL -- "-$CHILD_PID" 2>/dev/null
    sleep 0.1
    kill -0 -- "-$CHILD_PID" 2>/dev/null \
      && err "sandbox tree survived SIGKILL (pgid $CHILD_PID) — inspect manually"
    CHILD_PID=""
  fi
  [[ -n "${FUSE_PID:-}" ]] && kill "$FUSE_PID" 2>/dev/null
  # 2. ro-bind: make traversable again, then restore EXACT original modes
  local p mf mode path
  for p in "${CLEAN_RO[@]:-}"; do [[ -n $p && -e $p ]] && chmod -R u+w -- "$p" 2>/dev/null; done
  for mf in "${RO_MODES[@]:-}"; do
    [[ -n $mf && -f $mf ]] || continue
    while IFS='|' read -r mode path; do
      [[ -n "$mode" && -e "$path" ]] && chmod "$mode" -- "$path" 2>/dev/null
    done < "$mf"
    rm -f -- "$mf"
  done
  # 3. temp dirs / ephemeral homes
  for p in "${CLEAN_TMPDIRS[@]:-}"; do [[ -n $p && -d $p ]] && rm -rf -- "$p" 2>/dev/null; done
  [[ -n "$CLEAN_EPH_HOME" && -d "$CLEAN_EPH_HOME" ]] && rm -rf -- "$CLEAN_EPH_HOME" 2>/dev/null
  return $rc
}
on_sig() {
  local sig="$1"
  say "signal caught — killing sandbox tree (process group)"
  if [[ -n "${CHILD_PID:-}" ]]; then
    kill -TERM -- "-$CHILD_PID" 2>/dev/null
    sleep 0.5
    kill -KILL -- "-$CHILD_PID" 2>/dev/null
  fi
  exit $(( 128 + sig ))
}
trap cleanup EXIT
trap 'on_sig 2' INT
trap 'on_sig 15' TERM

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

# --- precedence honesty (flag interactions that silently surprise) ----------
if [[ $EPHEMERAL_EXPLICIT == 1 && "$BOX_NAME" != default ]]; then
  warn "--ephemeral wins: '--home $BOX_NAME' is ignored for this run"
fi
[[ -n "$SANDBOX_LABEL" && "$BOX_NAME" != default && $EPHEMERAL == 0 ]] \
  && warn "--label ignored with a persistent --home (sandbox id = home name)"
[[ $EPHEMERAL_JAIL == 1 && -z "$JAIL" ]] \
  && warn "--ephemeral-jail without --jail: nothing to clone"
[[ -n "$SCRIPT_FILE" && ${#CMD[@]} -gt 0 ]] \
  && warn "--script ignored: an explicit command was given"

# --- netblock env tamper guard ----------------------------------------------
# the netblock is an env-based shim; a naive or hostile env must not disarm it
if [[ $NETBLOCK == 1 ]]; then
  for kv in "${ENVS[@]:-}"; do
    case "$kv" in LD_PRELOAD=*|TW_NETBLOCK=*|TW_NETBLOCK_LOG=*)
      die "refusing --setenv $kv: it would bypass --unshare-net" ;; esac
  done
  for k in "${UNSETS[@]:-}"; do
    case "$k" in LD_PRELOAD|TW_NETBLOCK|TW_NETBLOCK_LOG)
      die "refusing --unsetenv $k: it would bypass --unshare-net" ;; esac
  done
fi

# --- ro-bind × fakeroot guard -------------------------------------------------
# proot's fake_id0 (-0) extension really chmods host files writable whenever
# the fake-root guest writes them — silently defeating chmod-based ro-bind.
if [[ ${#USER_RBINDS[@]} -gt 0 && $FAKE_ROOT == 1 && "${TW_ALLOW_ROBIND_FAKE:-0}" != 1 ]]; then
  err "--ro-bind under fakeroot (-0, the default) is NOT write-protected:"
  err "  proot's fake_id0 lifts host file modes so the fake-root guest can write."
  die "fix: add --no-fakeroot for enforced read-only binds, or set TW_ALLOW_ROBIND_FAKE=1 to accept the risk"
fi
[[ ${#USER_RBINDS[@]} -gt 0 && $FAKE_ROOT == 1 ]] \
  && warn "TW_ALLOW_ROBIND_FAKE=1: --ro-bind paths are NOT write-protected under fakeroot"

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
  if [[ $DRY_RUN == 1 ]]; then
    BOX_HOME="$TW_HOME/tmp/home-$SID.dryrun"   # printed, never created
  else
    BOX_HOME="$(mktemp -d "$TW_HOME/tmp/home-$SID.XXXXXX")" || die "cannot create ephemeral home"
    CLEAN_EPH_HOME="$BOX_HOME"
  fi
else
  BOX_HOME="$TW_HOME/home/$BOX_NAME"; [[ $DRY_RUN == 1 ]] || mkdir -p "$BOX_HOME"
fi

# provision rc + notice (idempotent: don't clobber user edits)
if [[ $DRY_RUN == 0 ]]; then
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
fi

# --- jail binding ---------------------------------------------------------------
JAIL_BIND_SRC=""
if [[ -n "$JAIL" ]]; then
  local_j="$(jail_dir "$JAIL")"
  [[ -d "$local_j" && -f "$local_j/.tw-jail" ]] || die "jail '$JAIL' missing — build it: tw jail build $JAIL"
  if [[ "$EPHEMERAL_JAIL" == 1 ]]; then
    if [[ $DRY_RUN == 1 ]]; then
      say "dry-run: jail '$JAIL' would be cloned per-run; using base path in the preview"
    else
      say "cloning jail '$JAIL' for single run (cp -a)…"
      run_j="$(mktemp -d "$TW_HOME/tmp/jail-$SID.XXXXXX")"
      cp -a "$local_j/." "$run_j/" || die "jail clone failed"
      CLEAN_TMPDIRS+=("$run_j")       # wipe the sacrificial copy at exit
      local_j="$run_j"
    fi
  fi
  JAIL_BIND_SRC="$local_j"
fi

# --- read-only snapshot: chmod a-w, EXACT mode restore in cleanup -------------
for spec in "${USER_RBINDS[@]:-}"; do
  [[ -z "$spec" ]] && continue
  src="${spec%%:*}"
  [[ -e "$src" ]] || die "--ro-bind source missing: $src"
  if [[ $DRY_RUN == 1 ]]; then
    [[ $QUIET == 0 ]] && ok "ro-bind: ${C_DIM}$src${C_RST} (dry-run: perms untouched)"
    continue
  fi
  mf="$TW_HOME/tmp/modes.$(rand_id).lst"
  find "$src" -exec stat -c '%a|%n' {} + 2>/dev/null > "$mf" || true
  if chmod -R a-w -- "$src" 2>/dev/null; then
    CLEAN_RO+=("$src"); RO_MODES+=("$mf")
    [[ $QUIET == 0 ]] && ok "ro-bind: ${C_DIM}$src${C_RST} (a-w snapshot, exact restore armed)"
  else
    rm -f -- "$mf"
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

# --- script staging ------------------------------------------------------------
if [[ -n "$SCRIPT_FILE" && ${#CMD[@]} -eq 0 ]]; then
  if [[ $DRY_RUN == 0 ]]; then
    cp -f "$SCRIPT_FILE" "$BOX_HOME/.tw-entry" 2>/dev/null || die "cannot stage $SCRIPT_FILE"
    chmod +x "$BOX_HOME/.tw-entry" 2>/dev/null
  fi
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
# user env FIRST, netblock env LAST: env(1) lets later assignments win, so the
# shim can never be shadowed by a user-supplied LD_PRELOAD / TW_NETBLOCK
for kv in "${ENVS[@]:-}"; do [[ -n $kv ]] && EOPTS+=("$kv"); done
[[ $NETBLOCK == 1 ]] && EOPTS+=("TW_NETBLOCK=1" "LD_PRELOAD=$NETBLOCK_SO")
# log blocked socket attempts into the audit stream when auditing
[[ $NETBLOCK == 1 && -n "$AUDIT" ]] && EOPTS+=("TW_NETBLOCK_LOG=1")

# --- resource cage (runs as a bash preamble inside proot) --------------------------
# NOTE: unsupported limits are REPORTED, not silently dropped
PRE="ulimit -Sc 0 2>/dev/null || echo 'tw: ulimit -Sc 0 not applied' >&2; "
[[ -n "$LIM_FILES" ]] && PRE+="ulimit -n $LIM_FILES 2>/dev/null || echo 'tw: ulimit -n $LIM_FILES not applied' >&2; "
[[ -n "$LIM_PROCS" ]] && PRE+="ulimit -u $LIM_PROCS 2>/dev/null || echo 'tw: ulimit -u $LIM_PROCS not applied' >&2; "
[[ -n "$LIM_FSIZE" ]] && PRE+="ulimit -f $(( LIM_FSIZE * 1024 )) 2>/dev/null || echo 'tw: ulimit -f not applied' >&2; "
[[ -n "$LIM_MEM" ]]   && PRE+="ulimit -v $(( LIM_MEM * 1024 )) 2>/dev/null || echo 'tw: ulimit -v not applied' >&2; "

INNER=( env "${EOPTS[@]}" bash -c "${PRE}exec \"\$@\"" "tw-sh" "${CMD[@]}" )

FULL=( proot "${PARGS[@]}" -w "$GCWD" "${INNER[@]}" )
[[ "$NICE_L" != 0 ]] && FULL=( nice -n "$NICE_L" "${FULL[@]}" )
# the --timeout fuse is enforced by tw itself (TERM→KILL on the sandbox
# process group) — see the launch section. A coreutils `timeout -s KILL`
# wrapper would SIGKILL proot and orphan every tracee.

# --- netblock sanity ------------------------------------------------------------------
if [[ $NETBLOCK == 1 && ! -f "$NETBLOCK_SO" ]]; then
  die "netblock shim missing — run the installer (builds $NETBLOCK_SO)"
fi

# --- dry run -----------------------------------------------------------------------
if [[ $DRY_RUN == 1 ]]; then
  say "dry-run — nothing executed, no persistent state changed"
  [[ ${#RO_MODES[@]} -eq 0 ]] || say "        (ro-bind permissions left untouched in dry-run)"
  printf '%s' "$C_DIM"
  printf '  %q' "${FULL[@]}" | fold -s -w 100 | sed 's/^/  /'
  printf '%s\n' "$C_RST"
  exit 0
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
# setsid: the whole sandbox tree (tracer + tracees) lands in its OWN process
# group, so tw can TERM→KILL all of it. Without a dedicated group, killing the
# group would kill tw itself — and killing just the tracer ORPHANS the tracees
# (the v0.1.0 teardown bug: guests surviving fuse/signals).
HAS_SETSID="$(command -v setsid || true)"
[[ -z "$HAS_SETSID" && $QUIET == 0 ]] && warn "setsid not found — teardown is best-effort (pkg install util-linux)"
T0=$(date +%s)
if [[ -n "$HAS_SETSID" ]]; then
  if [[ -n "$AUDIT_FILE" ]]; then setsid "${FULL[@]}" 2> "$AUDIT_FILE" & CHILD_PID=$!
  else setsid "${FULL[@]}" & CHILD_PID=$!; fi
else
  # fallback: same process group as tw — only the tracer can be signalled
  if [[ -n "$AUDIT_FILE" ]]; then "${FULL[@]}" 2> "$AUDIT_FILE" & CHILD_PID=$!
  else "${FULL[@]}" & CHILD_PID=$!; fi
fi

# fuse: TERM the sandbox group first (proot unwinds, --kill-on-exit runs),
# KILL after a 3s grace. The watcher exits early if the tree dies on its own.
if [[ $TIMEOUT != 0 && -n "$CHILD_PID" ]]; then
  (
    for (( _i=0; _i<TIMEOUT; _i++ )); do
      sleep 1; kill -0 -- "-$CHILD_PID" 2>/dev/null || exit 0
    done
    kill -TERM -- "-$CHILD_PID" 2>/dev/null
    for (( _i=0; _i<3; _i++ )); do
      sleep 1; kill -0 -- "-$CHILD_PID" 2>/dev/null || exit 0
    done
    kill -KILL -- "-$CHILD_PID" 2>/dev/null
  ) & FUSE_PID=$!
fi

wait "$CHILD_PID"; RC=$?
# never claim a clean teardown until the tree is verifiably gone
if [[ -n "${CHILD_PID:-}" ]] && kill -0 -- "-$CHILD_PID" 2>/dev/null; then
  kill -KILL -- "-$CHILD_PID" 2>/dev/null
  sleep 0.2
  kill -0 -- "-$CHILD_PID" 2>/dev/null && TREE_ALIVE=1 || TREE_ALIVE=0
fi
CHILD_PID=""
T1=$(date +%s)

# --- epilogue -----------------------------------------------------------------------------
if [[ -n "$AUDIT_FILE" ]]; then
  nx=$(awk '/execve/{n++} END{print n+0}' "$AUDIT_FILE" 2>/dev/null)
  nb=$(awk '/tw-net/{n++} END{print n+0}'  "$AUDIT_FILE" 2>/dev/null)
  [[ $QUIET == 0 ]] && say "audit → ${C_DIM}$AUDIT_FILE${C_RST}  (${nx:-0} execve · ${nb:-0} netblocks)"
fi
if [[ $TIMEOUT != 0 && ( ( $RC -ge 124 && $RC -le 137 ) || $((T1-T0)) -ge $TIMEOUT ) ]]; then
  warn "fuse blown: sandbox tree TERMinated (+KILL grace) after ${TIMEOUT}s"
fi
if [[ $TREE_ALIVE == 1 ]]; then
  err "WARNING: sandbox processes SURVIVED teardown — this run was NOT fully contained"
fi
if [[ $QUIET == 0 ]]; then
  emo="[ok]"; [[ $RC != 0 ]] && emo="[x]"
  fate="tree reaped"; [[ $TREE_ALIVE == 1 ]] && fate="TREE NOT REAPED"
  printf '%s%s%s sandbox %s torn down · %ss · exit %d · %s\n' \
    "${C_DIM}" "$emo" "${C_RST}" "$SID" "$((T1-T0))" "$RC" "$fate" >&2
fi
exit "$RC"
__TW_PAYLOAD_SCRIPT__
  chmod 0755 "$BIN_DIR/tw"
fi
ok "installed: $BIN_DIR/tw"

# --- 3. netblock shim ------------------------------------------------------------
mkdir -p "$LIB_DIR"
if [[ -f "$PWD/tw-netblock.c" ]]; then
  say "using local ./tw-netblock.c"; cp "$PWD/tw-netblock.c" "$BUILD_DIR/"
else
  cat > "$BUILD_DIR/tw-netblock.c" <<'__TW_PAYLOAD_C__'
// ============================================================================
//  tw-netblock — LD_PRELOAD network kill-switch for termwrap sandboxes
//
//  Intercepts libc socket()/getaddrinfo()/connect(). When the env var
//  TW_NETBLOCK=1 the sandbox fails CLOSED for AF_INET / AF_INET6 /
//  AF_NETLINK+AF_PACKET traffic with EACCES, so dynamically-linked agents
//  (python, node, ruby, curl, wget, git …) simply cannot open sockets.
//
//  Build:  cc -O2 -shared -fPIC tw-netblock.c -o netblock.so
//
//  Scope note: raw-syscall binaries (static, most Go) bypass LD_PRELOAD —
//  this is a safety rail for AI agents, not a kernel netns. See tw --caveats.
//
//  COPYRIGHT OPENTODO© — released under the MIT license.
// ============================================================================
#define _GNU_SOURCE
#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <dlfcn.h>

static int enabled(void) {
  const char *v = getenv("TW_NETBLOCK");
  return v && v[0] == '1';
}
static int loud(void) {
  return getenv("TW_NETBLOCK_LOG") != NULL;
}
static void note(const char *op, int domain) {
  if (loud())
    fprintf(stderr, "[tw-net] blocked %s(domain=%d) — sandbox is offline by policy\n",
            op, domain);
}
static int deny_domain(int d) {
  return d == AF_INET || d == AF_INET6 || d == AF_PACKET || d == AF_NETLINK;
}

typedef int (*socket_fn)(int, int, int);
typedef int (*connect_fn)(int, const struct sockaddr *, socklen_t);
typedef int (*ga_fn)(const char *, const char *, const struct addrinfo *,
                     struct addrinfo **);

int socket(int domain, int type, int protocol) {
  if (enabled() && deny_domain(domain)) {
    note("socket", domain);
    errno = EACCES;
    return -1;
  }
  static socket_fn real = NULL;
  if (!real) real = (socket_fn)dlsym(RTLD_NEXT, "socket");
  return real(domain, type, protocol);
}

// second line of defense for resolvers that grabbed a socket elsewhere
int connect(int fd, const struct sockaddr *addr, socklen_t len) {
  if (enabled() && addr &&
      (addr->sa_family == AF_INET || addr->sa_family == AF_INET6)) {
    note("connect", addr->sa_family);
    errno = EACCES;
    return -1;
  }
  static connect_fn real = NULL;
  if (!real) real = (connect_fn)dlsym(RTLD_NEXT, "connect");
  return real(fd, addr, len);
}

// fast, quiet failure for DNS so agents do not stall on timeouts
int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **res) {
  if (enabled() && (!hints || hints->ai_family != AF_UNIX)) {
    if (loud())
      fprintf(stderr, "[tw-net] blocked getaddrinfo(\"%s\")\n",
              node ? node : "(null)");
    return EAI_NONAME;
  }
  static ga_fn real = NULL;
  if (!real) real = (ga_fn)dlsym(RTLD_NEXT, "getaddrinfo");
  return real(node, service, hints, res);
}
__TW_PAYLOAD_C__
fi
say "compiling netblock.so …"
cc -O2 -shared -fPIC "$BUILD_DIR/tw-netblock.c" -o "$LIB_DIR/netblock.so" \
  || cc -O2 -shared -fPIC "$BUILD_DIR/tw-netblock.c" -o "$LIB_DIR/netblock.so" -ldl \
  || die "compile failed"
ok "built: $LIB_DIR/netblock.so"

# --- 4. default profiles ---------------------------------------------------------
mkdir -p "$PROFILE_DIR" "$TW_HOME/profiles.d"
cat > "$PROFILE_DIR/ai-agent.conf" <<'__TW_PAYLOAD_PROFILE__'
# =============================================================================
# termwrap profile: ai-agent
#
# One flag per line. '#' starts a comment. Applied BEFORE your CLI flags,
# so anything you pass on the command line still wins.
#
# Use:
#   tw --profile ai-agent -- <your agent command>
# Strong mode (recommended): jail the whole $PREFIX snapshot too
#   tw jail build stock            # one-time, ~size of your $PREFIX
#   tw --profile ai-agent --jail stock -- <your agent command>
# =============================================================================

# -- lifecycle: brand-new $HOME every run, wiped at exit ----------------------
--ephemeral

# -- filesystem view: secrets simply do not exist for the guest ---------------
--hide ~/.ssh
--hide ~/.gnupg
--hide ~/.netrc
--hide ~/.git-credentials
--hide ~/.termux
--hide ~/.config/gh
--hide /sdcard

# -- transport: fail-closed sockets (libc-level; see tw --caveats) ------------
--unshare-net

# -- resources: a runaway agent gets a cage, not your device ------------------
--max-procs 256
--max-files 512
--nice 10
--timeout 900

# -- observability: every execve + path rewrite into the audit log ------------
--audit ai-agent.log

# want a *host* scratch dir the agent may read? expose it explicitly:
# --bind ~/shared-inbox
# want a result dir the agent may write? expose it explicitly:
# --bind ~/agent-outbox
__TW_PAYLOAD_PROFILE__
[[ -f "$PWD/agent-guard.sh" ]] && install -m 0755 "$PWD/agent-guard.sh" "$BIN_DIR/tw-agent-guard" || true
ok "profile installed: ai-agent (~override in $TW_HOME/profiles.d/)"

# --- 5. verify -------------------------------------------------------------------
say "running selftest…"
"$BIN_DIR/tw" --selftest || warn "selftest reported issues — read above"

printf '\n%s┌─ installed ─────────────────────────────%s\n' "$D" "$Z"
printf '%s│%s tw --help            flag reference\n' "$D" "$Z"
printf '%s│%s tw --caveats         honest threat model\n' "$D" "$Z"
printf '%s│%s tw jail build stock  rm-proof prefix jail\n' "$D" "$Z"
printf '%s│%s tw --profile ai-agent -- <cmd>   run an agent\n' "$D" "$Z"
printf '%s└─────────────────────────────────────────%s\n' "$D" "$Z"
ok "termwrap v0.2.0 ready — trust nothing, run anything."

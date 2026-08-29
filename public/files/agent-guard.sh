#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# agent-guard — run LLM-proposed shell commands through termwrap, one by one
#
# The pattern: the MODEL proposes, the SANDBOX disposes.
# Reads commands (one per line; '#' = comment = shown as rationale) from a
# file or stdin, executes each inside a fresh termwrap sandbox, prints a
# compact verdict per command. Exit code = number of failed commands.
#
#   ./agent-guard.sh [plan.txt]            # ask before every command
#   ./agent-guard.sh -y [plan.txt]         # YOLO: run all, still sandboxed
#   llm "propose steps to ..." | ./agent-guard.sh
#
# Env knobs:  TW_FLAGS='--profile ai-agent --jail stock'   TW_TIMEOUT=600
#
#  COPYRIGHT OPENTODO© — released under the MIT license.
# =============================================================================
set -uo pipefail

ASSUME_YES=0
[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && { ASSUME_YES=1; shift; }
SRC="${1:-/dev/stdin}"

TW_FLAGS="${TW_FLAGS:---profile ai-agent --jail stock}"
TW_TIMEOUT="${TW_TIMEOUT:-600}"

GRN=$'\033[38;5;114m'; RED=$'\033[38;5;203m'; AMB=$'\033[38;5;215m'
DIM=$'\033[2m'; RST=$'\033[0m'

ran=0; failed=0; step=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" == \#* ]]; then
    printf '%s# %s%s\n' "$DIM" "${line#\# }" "$RST"; continue
  fi
  step=$((step+1))
  printf '\n%s┌ step %02d%s %s%s%s\n' "$DIM" "$RST" "$GRN" "$line" "$RST"

  if [[ $ASSUME_YES == 0 ]]; then
    printf '  run in sandbox? [y/N/e=edit] '; read -r a < /dev/tty || a=n
    case "$a" in
      y|Y) : ;;
      e|E) printf '  edit> '; read -r line < /dev/tty || exit 1 ;;
      *) printf '  %sskipped%s\n' "$DIM" "$RST"; continue ;;
    esac
  fi

  ran=$((ran+1))
  # shellcheck disable=SC2086
  timeout "$TW_TIMEOUT" tw --quiet $TW_FLAGS -- bash -lc "$line"
  rc=$?
  if [[ $rc == 0 ]]; then
    printf '%s└ verdict:%s OK (exit 0)\n' "$GRN" "$RST"
  elif [[ $rc -ge 124 ]]; then
    failed=$((failed+1)); printf '%s└ verdict:%s FUSE BLOWN (timeout %ss)\n' "$AMB" "$RST" "$TW_TIMEOUT"
  else
    failed=$((failed+1)); printf '%s└ verdict:%s FAILED (exit %d)\n' "$RED" "$RST" "$rc"
  fi
done < "$SRC"

printf '\n%s::%s guard summary — %d ran · %d failed · host untouched\n' \
  "$DIM" "$RST" "$ran" "$failed"
exit "$failed"

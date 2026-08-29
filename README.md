# termwrap (tw)

> **A bubblewrap-style sandbox that actually works on stock, unrooted Android.**
> Isolate AI agents and semi-trusted automation in Termux — powered by ptrace, not namespaces. No root. No user namespaces. No kernel patches.

`termwrap` (command: `tw`) gives every run its own fake root, its own `$HOME`, an optional cut network cable, resource cages, a hard timeout, a tar-snapshot jail over your real `$PREFIX`, and a full audit trail — with bubblewrap-flavoured flags, in one shell script.

```
tw --profile ai-agent --jail stock --timeout 900 -- python agent.py
```

- **Version:** 0.1.0 · **License:** MIT · **Platform:** Termux on Android (aarch64 / arm / x86_64)
- **Requires:** [Termux](https://f-droid.org/en/packages/com.termux/), `proot`, `coreutils`, `tar`, `findutils`, `clang` (the installer handles all of it)
- **Threat model:** AI agents & semi-trusted automation — *not* actively malicious native code (read [`tw --caveats`](#-threat-model--honest-limitations))

---

## Table of contents

1. [Why](#why)
2. [How it works](#how-it-works)
3. [Install](#install)
4. [Quick start](#quick-start)
5. [Flag reference](#flag-reference)
6. [Profiles](#profiles)
7. [Jails — rm-proof `$PREFIX`](#jails--rm-proof-prefix)
8. [Network kill-switch (`tw-netblock`)](#network-kill-switch-tw-netblock)
9. [`agent-guard` — model proposes, sandbox disposes](#agent-guard--model-proposes-sandbox-disposes)
10. [State on disk](#state-on-disk)
11. [Diagnostics & selftest](#diagnostics--selftest)
12. [Environment variables](#environment-variables)
13. [Exit codes](#exit-codes)
14. [🔒 Threat model — honest limitations](#-threat-model--honest-limitations)
15. [FAQ](#faq)
16. [Repository layout](#repository-layout)
17. [Developing the website](#developing-the-website)
18. [License](#license)

---

## Why

You want to run an AI agent (or any script you only half-trust) on your phone, inside Termux. On a desktop you'd reach for bubblewrap — but bubblewrap needs the kernel to let an unprivileged user create user + mount namespaces (`CONFIG_USER_NS`), and **stock Android kernels ship with that disabled or blocked behind SELinux**. Every "bwrap on Termux" attempt hits the same wall:

```
bwrap: setting up uid map: Permission denied
```

`termwrap` sidesteps the question entirely by building isolation from a primitive Android *does* allow between same-uid processes: **ptrace(2)** — the same mechanism [proot](https://proot-me.github.io/) has used for years. On top of that primitive it layers a few honest side-channels: an `LD_PRELOAD` socket kill-switch, ulimits, a hard timeout, and tar-snapshot "jails" of `$PREFIX` for destructive-proof runs.

## How it works

Each `tw` run assembles a `proot` invocation plus environment plumbing, launches it, and tears everything down on exit:

```
┌──────────────────────────────────────────────────────────────────────┐
│  your Termux session (real $HOME, real $PREFIX, uid 10xxx)           │
│                                                                      │
│  ┌────────────────── termwrap sandbox (sid 4ecc5a) ────────────────┐ │
│  │                                                                 │ │
│  │  proot (ptrace tracer)                                          │ │
│  │  ├─ -0              fake uid 0 inside the box                   │ │
│  │  ├─ -b BOX_HOME:$HOME   sandbox home shadows your real home     │ │
│  │  ├─ -b jail:$PREFIX     optional tar snapshot over $PREFIX      │ │
│  │  ├─ -b overlay:$PREFIX/tmp  fresh /tmp per run (default)        │ │
│  │  ├─ -b empty:PATH       --hide / --tmpfs overlays               │ │
│  │  ├─ --kill-on-exit      tracees die with the tracer             │ │
│  │  └─ -v 9                optional audit trace (--audit)          │ │
│  │                                                                 │ │
│  │  env LD_PRELOAD=netblock.so   socket()/connect()/getaddrinfo()  │ │
│  │  │                             fail closed with EACCES          │ │
│  │  bash -c 'ulimit …; exec "$@"'   resource cage preamble         │ │
│  │  timeout -k 3 -s KILL N          optional fuse                  │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

What a default run gives you:

| Layer | Mechanism | Protects against |
|---|---|---|
| **Fake root** | `proot -0` | tools that insist on being root |
| **Shadowed `$HOME`** | persistent or ephemeral sandbox home bound over your real `$HOME` | agents reading `~/.ssh`, dotfiles, credentials |
| **Fresh `/tmp`** | empty overlay over `$PREFIX/tmp` | cross-run temp sniffing |
| **Hidden paths** | empty-dir/`/dev/null` overlays (`--hide`) | secrets that "don't exist" for the guest |
| **Network off** | `LD_PRELOAD` shim (`--unshare-net`) | exfiltration via python/node/curl/wget/git… |
| **Resource cage** | `ulimit` prologue (`--max-procs/files/fsize/mem`, `--nice`) | fork bombs, runaway memory, disk stuffing |
| **Fuse** | `timeout -k 3 -s KILL N` | forever-loops, hung downloads |
| **Jail** | tar snapshot of `$PREFIX` bound read-implications-aside over the real one | `rm -rf $PREFIX`, package mangling |
| **Audit** | `proot -v 9` trace (`--audit FILE`) | "what did it actually run?" |

## Install

Inside Termux:

```bash
curl -fsSL https://open-todo.github.io/TermWrap/files/install.sh | bash
```

The installer is idempotent and self-contained (it embeds every payload, so it works even if you download just that one file). It:

1. installs dependencies — `proot coreutils tar findutils clang`
2. installs `tw` → `$PREFIX/bin/tw`
3. compiles the netblock shim → `$PREFIX/lib/termwrap/netblock.so`
4. installs the `ai-agent` profile → `$PREFIX/share/termwrap/profiles/`
5. runs `tw --selftest`

Manual install: copy `app/termwrap.sh` to `$PREFIX/bin/tw`, `chmod +x` it, then `pkg install proot coreutils tar findutils clang` and build the shim with `cc -O2 -shared -fPIC tw-netblock.c -o $PREFIX/lib/termwrap/netblock.so`. Re-run the installer any time to upgrade.

## Quick start

```bash
# a shell in a throwaway sandbox (fresh home, fresh /tmp, fake root)
tw --ephemeral

# the agent combo: jailed prefix, no net, 15-minute fuse, full audit
tw jail build stock              # one-time snapshot of your $PREFIX
tw --profile ai-agent --jail stock -- python3 agent.py

# network-isolated build with limits
tw --unshare-net --max-procs 256 --max-mem 2048 --timeout 600 -- make -j4

# expose exactly one host folder, read-only, hide your secrets
tw --ro-bind ~/dataset --hide ~/.ssh -- npm test

# run a host script inside the box without changing its invocation
tw --ephemeral --script ./untrusted.sh

# what would run, without running it
tw --dry-run --profile ai-agent -- bash -c 'echo hi'
```

General form:

```
tw [FLAGS] [--] CMD [ARGS...]     # no CMD → interactive login shell
tw jail <build|rebuild|discard|list|path> [NAME]
tw --selftest | --caveats | --help | --version
```

Flags may also be written `--flag=value`. Paths are `~`-expanded and made absolute against your cwd. Everything before `--` is termwrap's; everything after is the guest command.

## Flag reference

**Filesystem view**

| Flag | Meaning |
|---|---|
| `--bind SRC[:DST]` | bind host path into the guest, read-write |
| `--ro-bind SRC[:DST]` | bind read-only — enforced by a `chmod a-w` snapshot, restored on exit (best-effort; crash windows and already-open fds are not covered) |
| `--dev-bind SRC[:DST]` | bind device nodes (same mechanism, flag parity with bwrap) |
| `--hide PATH` (alias `--deny`) | shadow a host path — dirs get an empty overlay, files get `/dev/null` |
| `--tmpfs PATH` | empty writable overlay at a guest path |
| `--rootfs DIR` | advanced: use DIR as the guest root (`proot -r`) instead of the in-place view |
| `-w, --workdir DIR` | guest working directory (default: sandbox `$HOME`) |

**Identity / lifecycle**

| Flag | Meaning |
|---|---|
| `--home NAME` | use (or create) a persistent named home under `$TW_HOME/home/NAME` (default: `default`) |
| `--ephemeral` | brand-new `$HOME` for this run, wiped on exit |
| `--jail NAME` | bind a tar-snapshot jail over `$PREFIX` — destructive ops hit the snapshot, never your real install |
| `--ephemeral-jail` | clone the jail per run and discard it after (slow, paranoid) |
| `--script FILE` | bind a host script into the guest and execute it (used when no `CMD` is given) |
| `--label ID` | custom sandbox id shown in banners, prompts and logs |
| `--allow-nested` | permit `tw` inside `tw` (refused by default — agents love to re-sandbox) |

**Environment**

| Flag | Meaning |
|---|---|
| `--clearenv` | scrub the environment; keep only `HOME`, `PATH`, `TERM`, `TMPDIR`, `PREFIX`, `LANG` |
| `--setenv K=V` | inject a variable |
| `--unsetenv K` | drop a variable |

**Transport / resources**

| Flag | Meaning |
|---|---|
| `--unshare-net` (alias `--no-net`) | fail-closed network via the `LD_PRELOAD` socket shim |
| `--timeout SECONDS` | hard-kill the whole tree after N seconds |
| `--max-procs N` | `ulimit -u` |
| `--max-files N` | `ulimit -n` |
| `--max-fsize MB` | `ulimit -f` |
| `--max-mem MB` | `ulimit -v` (address space) |
| `--nice N` | scheduling niceness 0–19 |

**Observability**

| Flag | Meaning |
|---|---|
| `--audit FILE` | `proot -v9` systrace → FILE (relative paths land in `$TW_HOME/logs/`) |
| `--dry-run` | print the exact `proot` command line, change nothing |
| `-q, --quiet` | suppress banners |

**tmp policy / root faking**

| Flag | Meaning |
|---|---|
| `--fresh-tmp` | empty overlay on `$PREFIX/tmp` (default) |
| `--share-tmp` | expose the real `$PREFIX/tmp` |
| `-0, --fakeroot` | fake uid 0 (default) |
| `--no-fakeroot` | keep the real uid |

## Profiles

A profile is just a file of flags — one per line, `#` comments — spliced in **before** your CLI flags, so anything you pass explicitly still wins.

```
tw --profile ai-agent -- python3 agent.py     # system profile
tw --profile ~/my-box.conf -- bash            # any path
```

Search order: `$TW_HOME/profiles.d/NAME.conf` → `$TW_HOME/profiles.d/NAME` → `$TW_SHARE/profiles/NAME.conf` → `$TW_SHARE/profiles/NAME` (i.e. your overrides under `~/.local/share/termwrap/profiles.d/` beat the system copies). Profiles may include other profiles with `--profile`, up to depth 4.

Shipped profile [`app/ai-agent.conf`](app/ai-agent.conf):

```conf
--ephemeral              # fresh home every run
--hide ~/.ssh            # secrets simply do not exist for the guest
--hide ~/.gnupg
--hide ~/.netrc
--hide ~/.git-credentials
--hide ~/.termux
--hide ~/.config/gh
--hide /sdcard
--unshare-net            # fail-closed sockets
--max-procs 256          # a runaway agent gets a cage, not your device
--max-files 512
--nice 10
--timeout 900
--audit ai-agent.log     # every execve + path rewrite on record

# expose host dirs explicitly, only when you mean it:
# --bind ~/shared-inbox
# --bind ~/agent-outbox
```

## Jails — rm-proof `$PREFIX`

A jail is a full tar snapshot of your `$PREFIX` (minus `tmp/`, caches and logs) stored under `$TW_HOME/jails/NAME`. With `--jail NAME`, the snapshot is bound over your real `$PREFIX` for the run: the guest can `rm -rf /anything`, `pkg remove` the world, shred configs — it only ever touches the copy.

```bash
tw jail build stock          # one-time; ~ the size of your $PREFIX
tw jail list                 # name, size, path
tw jail rebuild stock        # refresh the snapshot after you pkg upgrade
tw jail discard stock        # reclaim space
tw jail path stock           # print where it lives
```

Add `--ephemeral-jail` to clone the jail per run (`cp -a`) and discard the clone on exit, so even the snapshot survives the session untouched. Jails cost disk and add copy overhead — rebuild them after package upgrades so they don't drift stale.

## Network kill-switch (`tw-netblock`)

`--unshare-net` loads `app/tw-netblock.c` (built to `$PREFIX/lib/termwrap/netblock.so` by the installer) via `LD_PRELOAD`. When `TW_NETBLOCK=1` it intercepts and **fails closed** with `EACCES`:

- `socket()` for `AF_INET` / `AF_INET6` / `AF_PACKET` / `AF_NETLINK`
- `connect()` to any IPv4/IPv6 address (second line of defense)
- `getaddrinfo()` → instant `EAI_NONAME`, so agents fail fast instead of stalling on DNS timeouts

Set `TW_NETBLOCK_LOG=1` (automatic when `--unshare-net` and `--audit` are combined) and every blocked call is logged into the audit stream, counted in the run summary as *netblocks*.

**Scope, honestly:** dynamically-linked Termux packages (python, node, ruby, curl, wget, git…) are covered. Static binaries and Go's raw-syscall dial path bypass `LD_PRELOAD`. This is an agent-safety rail, not a kernel netns.

## `agent-guard` — model proposes, sandbox disposes

[`app/agent-guard.sh`](app/agent-guard.sh) (installed as `tw-agent-guard`) is the reference harness for the two-phase agent loop: the LLM proposes shell commands, termwrap disposes of them safely. Feed it a plan file or stdin (one command per line, `#` lines are shown as rationale):

```bash
./agent-guard.sh plan.txt        # ask [y/N/e=edit] before every command
./agent-guard.sh -y plan.txt     # run all — still fully sandboxed
llm "propose steps to …" | ./agent-guard.sh
```

Each command runs in a fresh `tw` sandbox (`TW_FLAGS`, default `--profile ai-agent --jail stock`; `TW_TIMEOUT`, default 600) and gets a per-step verdict — `OK`, `FAILED (exit N)`, or `FUSE BLOWN`. The script's exit code is the number of failed commands, so CI can gate on it. Keep the agent's own API traffic on the host side of the loop; if it genuinely needs to fetch something, fetch on the host and pass results in via `--bind`.

## State on disk

Everything termwrap creates lives under one root — `$TW_HOME` (default `~/.local/share/termwrap`):

```
$TW_HOME/
├── home/           # persistent sandbox homes (--home NAME) — 'default' included
│   └── default/    #   .bashrc, .sandbox-notice, agent entrypoints
├── jails/          # tar-snapshot jails (--jail NAME), each with a .tw-jail manifest
├── logs/           # audit traces (--audit FILE with a relative path)
├── tmp/            # per-run scratch: tmp overlays, ephemeral homes, jail clones
└── profiles.d/     # your profile overrides (beat system profiles)
```

Homes are provisioned with a minimal `.bashrc` (sandbox-aware prompt, `tw-help` alias) and a `.sandbox-notice` file stating the sandbox id, mode, jail, network policy and where the real `$HOME` lives. Nothing is written outside `$TW_HOME`, `$PREFIX`'s install dirs, and the overlays you asked for.

## Diagnostics & selftest

```bash
tw --selftest    # termux env? proot present? exec smoke test? tools? netblock fails closed? state writable?
tw --caveats     # the honest limitations, printed to your terminal
tw --dry-run …   # print the exact proot command line; nothing executed
tw --audit …     # per-run trace: every execve + path rewrite, netblocks counted
```

The epilogue of every run summarizes wall time, exit code and (when auditing) `execve` / netblock counts.

## Environment variables

| Variable | Meaning |
|---|---|
| `TW_HOME` | state root (default `~/.local/share/termwrap`) |
| `TW_NETBLOCK_SO` | path to the shim (default `$PREFIX/lib/termwrap/netblock.so`) |
| `TW_NETBLOCK` / `TW_NETBLOCK_LOG` | set inside the guest by `--unshare-net` |
| `TW_SANDBOX_ID` | set inside the guest; its presence is what the nested-run guard checks |
| `TW_ALLOW_NESTED=1` | env-based alternative to `--allow-nested` |
| `TW_DEBUG=1` | `[dbg]` traces from the wrapper itself |
| `NO_COLOR` | disable ANSI colours |

## Exit codes

- The guest command's exit code is passed through verbatim.
- `124–137` under `--timeout` → the fuse blew; termwrap prints `[!] fuse blown`.
- Installer/config failures use exit `1` with an `[x]` message.

## 🔒 Threat model — honest limitations

Read this before trusting a run (`tw --caveats` prints it too).

1. **Same-uid ceiling.** proot rewrites paths, not capabilities. The guest keeps your Termux uid; a hostile native binary that ignores the filesystem (or knows ptrace tricks) can still poke you. For a real uid split, wrap whole sessions in an Android work profile (Shelter/Insular).
2. **Netblock scope.** The `--unshare-net` shim is `LD_PRELOAD` over libc `socket()`. Fail-closed for Termux packages; **static binaries and Go's raw-syscall dial path bypass it.** An agent-safety rail, not a netns.
3. **ro-bind is a chmod snapshot.** Enforced by `chmod a-w` before the run + restore after. Crash windows and already-open fds are outside the guarantee. For anything precious, `--hide` beats permissions.
4. **ptrace overhead.** fork/exec-heavy workloads pay 1.5–3×. Compute jobs without side effects belong outside the sandbox.
5. **No PID/IPC isolation.** The guest sees your process table and can signal within the uid. A cage of view, not of privilege.
6. **The point.** For AI agents the winning combo is `tw --profile ai-agent --jail stock --timeout 900 -- <agent>`: jail + netblock + audit + fuse, with secrets off-device.

**Android 12+ phantom-process killer:** long-running tracers can get culled by the OS. Disable it over adb:

```bash
adb shell settings put global settings_enable_monitor_phantom_procs false
```

## FAQ

**Why not just fix bwrap?**
bwrap needs unprivileged user+mount namespaces; stock Android kernels are built without `CONFIG_USER_NS` or wedge it behind SELinux. No userspace patch changes that without root. termwrap uses ptrace(2), which Android permits between same-uid processes — the proven proot-distro approach.

**Does it work on Android 12/13/14/15?**
Yes — everywhere Termux and proot run (aarch64/arm/x86_64). The one Android-ism is the phantom-process monitor above.

**How do I keep the agent online while the sandbox is offline?**
Two-phase loop: LLM API calls on the host, proposed commands in the box (`agent-guard.sh` shows the pattern). Need a resource? Fetch it host-side and pass it in via `--bind`.

**Can the agent escape and `rm` my real `$PREFIX`?**
With `--jail`, `$PREFIX` inside the run *is* a snapshot — let it shred the copy, `tw jail rebuild stock`, carry on. Your real install was never bound.

**How is this different from proot-distro?**
proot-distro puts you inside a foreign distro. termwrap sandboxes your *existing* Termux environment in place — same tools, same PATH, but selective visibility, no network, ulimits, timeouts, audit. They compose: run `tw` inside a distro too.

## Repository layout

The **app** and the **website** are fully isolated from each other:

```
TermWrap/
├── app/                    ← the product. Plain files, no build step, no website deps.
│   ├── termwrap.sh             the sandbox engine — installed as $PREFIX/bin/tw
│   ├── install.sh              self-contained curl|bash bootstrap (embeds all payloads)
│   ├── tw-netblock.c           LD_PRELOAD network kill-switch
│   ├── ai-agent.conf           default policy profile for AI agents
│   └── agent-guard.sh          model-proposes / sandbox-disposes loop
│
├── index.html              ← the website (landing page)
├── src/                        React + Tailwind source (hero, docs, FAQ, source browser…)
├── public/                     website-only static assets (favicon)
├── vite.config.ts              mounts app/ at /files/** (dev) and dist/files/ (build)
├── package.json / tsconfig.json
└── README.md                   ← you are here
```

The website never owns app code: `app/` is the single source of truth, and a tiny Vite plugin (`termwrapAppFiles` in `vite.config.ts`) *serves* it at `/files/*` so links like [`/files/install.sh`](http://localhost:5173/files/install.sh) and the site's source browser keep working — in dev (`vite dev`) and in production builds (`vite build` copies `app/` → `dist/files/`).

## Developing the website

```bash
npm install
npm run dev        # landing page at http://localhost:5173, app files at /files/*
npm run build      # single-file site in dist/ + dist/files/ (the app, copied in)
npm run preview    # serve the production build
```

To release the app itself, ship `app/` as-is — it has no build step. The installer even prefers sibling files (`./termwrap.sh`, `./tw-netblock.c`, …) next to itself, so a plain directory download works offline.

## License

MIT — © OPENTODO. See the headers of [`app/termwrap.sh`](app/termwrap.sh) and [`app/install.sh`](app/install.sh).

> **trust nothing, run anything.**

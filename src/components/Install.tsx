import { Terminal, FlaskConical, Ghost, Wand2 } from 'lucide-react';
import { Reveal, SectionHead, CopyButton, TermChrome } from './ui';
import { H_INSTALL_GH } from '../lib/data';

export function Install() {
  const installCmd = `curl -fsSL ${H_INSTALL_GH} | bash`;

  return (
    <section id="install" className="relative py-24 md:py-32">
      <div className="mx-auto max-w-6xl px-4 md:px-8">
        <SectionHead
          index="09"
          kicker="ship it"
          title="SIXTY SECONDS TO A CAGE"
          desc="Requirements: Termux (F-Droid or GitHub build), Android 8+, zero root. The installer is idempotent — re-run it any time to upgrade."
        />

        <div className="grid gap-6 lg:grid-cols-2">
          {/* step list */}
          <div className="space-y-5">
            {[
              {
                icon: Terminal,
                n: '01',
                t: 'bootstrap',
                body: 'One curl|bash straight from GitHub: pulls proot/coreutils/tar/clang/util-linux, installs tw, compiles netblock.so, seeds the ai-agent profile, self-tests.',
                cmd: installCmd,
              },
              {
                icon: FlaskConical,
                n: '02',
                t: 'verify the harness',
                body: 'End-to-end capability check: proot exec smoke, netblock fail-closed probe, state dir writability. Anything less than all-ok gets a loud report.',
                cmd: 'tw --selftest',
              },
              {
                icon: Ghost,
                n: '03',
                t: 'first sandbox',
                body: 'Ephemeral interactive shell with no network and no past. Type exit and the room burns behind you.',
                cmd: 'tw --ephemeral --unshare-net',
              },
              {
                icon: Wand2,
                n: '04',
                t: 'point an agent at it',
                body: 'Build the sacrificial jail once, then run your agent inside the full policy. Rebuild with `tw jail rebuild stock` whenever you want a fresh copy.',
                cmd: 'tw jail build stock && tw --profile ai-agent --jail stock -- ./agent',
              },
            ].map((s, i) => (
              <Reveal key={s.n} delay={i * 0.07}>
                <div className="panel group px-5 md:px-6 py-5">
                  <div className="flex items-center gap-3 mb-3">
                    <s.icon size={16} className="text-pho" />
                    <span className="text-[10px] tracking-[0.3em] text-dim">{s.n}</span>
                    <span className="font-disp text-[15px] font-semibold uppercase tracking-[0.15em] text-[#e6f4e6]">
                      {s.t}
                    </span>
                  </div>
                  <p className="text-[12.5px] leading-relaxed text-mist mb-4">{s.body}</p>
                  <div className="flex items-center gap-3 border border-line bg-ink/80 px-3 py-2.5">
                    <span className="text-pho text-xs shrink-0">$</span>
                    <code className="flex-1 truncate text-[11.5px] md:text-[12.5px] text-[#d9f8dd]">{s.cmd}</code>
                    <CopyButton text={s.cmd} className="!py-1 !px-2 shrink-0" />
                  </div>
                </div>
              </Reveal>
            ))}
          </div>

          {/* selftest preview + android 12 note */}
          <div className="space-y-5">
            <Reveal delay={0.1}>
              <div className="panel term-shadow lg:sticky lg:top-24">
                <TermChrome title="tw --selftest — expected output" />
                <div className="px-4 md:px-5 py-4 text-[11px] md:text-[12px] leading-[1.8]">
                  <div className="tl-ok">[ok] selftest: termux environment (/data/data/com.termux/files/usr)</div>
                  <div className="tl-ok">[ok] selftest: proot present (proot 5.x)</div>
                  <div className="tl-ok">[ok] selftest: proot exec smoke</div>
                  <div className="tl-ok">[ok] selftest: tool: tar · timeout · env · od · awk</div>
                  <div className="tl-ok">[ok] selftest: netblock shim present</div>
                  <div className="tl-ok">[ok] selftest: netblock fails closed (EACCES)</div>
                  <div className="tl-ok">[ok] selftest: state dir writable</div>
                  <div className="tl-sys">:: selftest: 9 ok · 0 fail</div>

                  <div className="mt-5 border border-amber/40 bg-amber/5 px-4 py-4">
                    <div className="flex items-center gap-2 text-amber text-[10px] uppercase tracking-[0.25em] mb-2">
                      <span>android 12+ pro-tip</span>
                    </div>
                    <p className="text-[11.5px] leading-relaxed text-mist mb-3">
                      Long-lived tracers trigger the phantom process killer. One adb line (or a
                      wireless-debug toggle) fixes it device-wide:
                    </p>
                    <div className="flex items-center gap-2 border border-amber/30 bg-ink/70 px-3 py-2">
                      <code className="flex-1 truncate text-[10.5px] md:text-[11px] text-amber/90">
                        adb shell settings put global settings_enable_monitor_phantom_procs false
                      </code>
                      <CopyButton
                        text="adb shell settings put global settings_enable_monitor_phantom_procs false"
                        className="!py-1 !px-2 shrink-0"
                      />
                    </div>
                  </div>

                  <div className="mt-5 border border-line bg-ink/60 px-4 py-4">
                    <div className="text-[10px] uppercase tracking-[0.25em] text-dim mb-2">prefer the audited path?</div>
                    <p className="text-[11.5px] leading-relaxed text-mist">
                      Every file lives in the repo under <span className="text-pho">app/</span> — raw from
                      GitHub (raw.githubusercontent.com/open-todo/TermWrap/main/app), mirrored here under <span className="text-pho">/files/</span>. Read
                      termwrap.sh in the source browser above, download it, <span className="text-[#d9f8dd]">install -m 0755 termwrap.sh $PREFIX/bin/tw</span> — no pipe required.
                    </p>
                  </div>
                </div>
              </div>
            </Reveal>
          </div>
        </div>
      </div>
    </section>
  );
}

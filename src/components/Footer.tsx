import { ArrowUpRight, TerminalSquare } from 'lucide-react';
import { ASCII_LOGO, H_INSTALL_URL } from '../lib/data';

export function Footer() {
  return (
    <footer className="relative border-t border-line bg-panel/40">
      <div className="mx-auto max-w-7xl px-4 md:px-8 py-16 md:py-20">
        <div className="grid gap-12 md:grid-cols-[1.2fr_1fr]">
          <div>
            <pre className="ascii text-[7px] sm:text-[9px] md:text-[10.5px] text-pho text-glow select-none">
              {ASCII_LOGO.join('\n')}
            </pre>
            <p className="mt-6 max-w-md text-[12.5px] leading-relaxed text-mist">
              termwrap — a bubblewrap-flavoured sandbox for Termux that runs on the
              devices bubblewrap gave up on. Built for the agentic era, on pocket
              hardware, with ptrace and spite.
            </p>
            <div className="mt-6 flex flex-wrap gap-3">
              <a
                href="/files/install.sh"
                className="inline-flex items-center gap-2 border border-pho/40 bg-pho/10 px-4 py-2.5 text-[11px] font-semibold uppercase tracking-[0.18em] text-pho hover:bg-pho hover:text-ink transition-colors"
              >
                <TerminalSquare size={13} /> install.sh
              </a>
              <a
                href="#source"
                className="inline-flex items-center gap-2 border border-line px-4 py-2.5 text-[11px] uppercase tracking-[0.18em] text-mist hover:text-pho hover:border-pho/40 transition-colors"
              >
                read the source <ArrowUpRight size={13} />
              </a>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-8 md:justify-items-end">
            <div>
              <div className="text-[10px] uppercase tracking-[0.3em] text-dim mb-4">docs</div>
              <ul className="space-y-2.5 text-[12px] text-mist">
                {[
                  ['#problem', 'why not bwrap'],
                  ['#arch', 'how it works'],
                  ['#flags', 'flag reference'],
                  ['#security', 'threat model'],
                  ['#faq', 'faq'],
                ].map(([h, l]) => (
                  <li key={h}>
                    <a href={h} className="hover:text-pho transition-colors">{l}</a>
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <div className="text-[10px] uppercase tracking-[0.3em] text-dim mb-4">files</div>
              <ul className="space-y-2.5 text-[12px] text-mist">
                {[
                  ['/files/termwrap.sh', 'termwrap.sh'],
                  ['/files/tw-netblock.c', 'tw-netblock.c'],
                  ['/files/ai-agent.conf', 'ai-agent.conf'],
                  ['/files/agent-guard.sh', 'agent-guard.sh'],
                  [H_INSTALL_URL, 'install.sh'],
                ].map(([h, l]) => (
                  <li key={h}>
                    <a href={h} className="hover:text-pho transition-colors">{l}</a>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>

        <div className="mt-14 flex flex-col md:flex-row items-start md:items-center justify-between gap-4 border-t border-line pt-6 text-[10.5px] uppercase tracking-[0.18em] text-dim">
          <span>
            <span className="text-pho font-bold">COPYRIGHT OPENTODO©</span> · MIT license · v0.1.0 · no trackers, no beacons
          </span>
          <span>
            made for <span className="text-pho">unrooted android</span> · same-uid ptrace, honest limits
          </span>
        </div>
      </div>
    </footer>
  );
}

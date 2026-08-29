import { AlertTriangle, ShieldAlert, Minus, Check, X } from 'lucide-react';
import { motion } from 'framer-motion';
import { Reveal, SectionHead } from './ui';
import { LIMITS, COMPARE } from '../lib/data';

const SEV = {
  high: { c: 'text-blood border-blood/40 bg-blood/5', label: 'hard truth' },
  med: { c: 'text-amber border-amber/40 bg-amber/5', label: 'soft spot' },
  info: { c: 'text-ice border-ice/40 bg-ice/5', label: 'know it' },
} as const;

function Cell({ v }: { v: string }) {
  if (v.startsWith('yes'))
    return (
      <span className="inline-flex items-center gap-1.5 text-pho">
        <Check size={12} /> {v.replace('yes', '').replace(/[()]/g, '').trim() || ''}
        {!v.replace('yes', '').replace(/[()]/g, '').trim() && <span className="sr-only">yes</span>}
      </span>
    );
  if (v.startsWith('no'))
    return (
      <span className="inline-flex items-center gap-1.5 text-blood/90">
        <X size={12} /> {v.replace('no', '').replace(/[()*]/g, '').trim()}
      </span>
    );
  if (v.startsWith('partial') || v.startsWith('n/a'))
    return (
      <span className="inline-flex items-center gap-1.5 text-dim">
        <Minus size={12} /> {v.replace(/[()]/g, '')}
      </span>
    );
  return <span className="text-mist">{v}</span>;
}

export function Security() {
  return (
    <section id="security" className="relative py-24 md:py-32">
      <div className="mx-auto max-w-7xl px-4 md:px-8">
        <SectionHead
          index="08"
          kicker="no security theater"
          title="READ THIS BEFORE YOU TRUST IT"
          desc="Every sandbox has a threat model. Most projects hide theirs; this one ships in `tw --caveats`. Here is exactly where the walls are thick — and where they are paper."
        />

        <div className="grid gap-5 md:grid-cols-2 lg:grid-cols-3">
          {LIMITS.map((l, i) => {
            const sev = SEV[l.sev];
            return (
              <motion.div
                key={l.title}
                initial={{ opacity: 0, y: 22 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-50px' }}
                transition={{ duration: 0.5, delay: (i % 3) * 0.07 }}
                className="panel relative px-6 py-6"
              >
                <span className={`inline-flex items-center gap-1.5 border px-2 py-0.5 text-[9px] uppercase tracking-[0.2em] ${sev.c}`}>
                  {l.sev === 'high' ? <ShieldAlert size={11} /> : <AlertTriangle size={11} />}
                  {sev.label}
                </span>
                <h3 className="mt-4 font-disp text-[16px] font-semibold text-[#e6f4e6]">{l.title}</h3>
                <p className="mt-3 text-[12px] leading-relaxed text-mist">{l.body}</p>
              </motion.div>
            );
          })}
        </div>

        {/* comparison */}
        <Reveal delay={0.1}>
          <div className="panel mt-14 overflow-hidden">
            <div className="border-b border-line bg-panel2/70 px-4 md:px-5 py-3.5">
              <span className="font-disp text-sm md:text-base font-semibold uppercase tracking-[0.18em] text-pho">
                the honest scoreboard
              </span>
              <span className="ml-3 text-[10px] uppercase tracking-[0.2em] text-dim">
                tw vs abwrap-android vs bubblewrap (rooted) vs proot-distro
              </span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[760px] text-left text-[11.5px] md:text-[12.5px]">
                <thead>
                  <tr className="border-b border-line text-[10px] uppercase tracking-[0.18em] text-dim">
                    <th className="px-4 md:px-5 py-3 font-medium">capability</th>
                    <th className="px-3 py-3 font-semibold text-pho">termwrap</th>
                    <th className="px-3 py-3 font-medium">abwrap</th>
                    <th className="px-3 py-3 font-medium">bwrap*</th>
                    <th className="px-3 py-3 font-medium">proot-distro</th>
                  </tr>
                </thead>
                <tbody>
                  {COMPARE.map((r) => (
                    <tr key={r.cap} className="border-b border-line/60 last:border-0 hover:bg-panel2/40 transition-colors">
                      <td className="px-4 md:px-5 py-3 text-[#d9e8d9]">{r.cap}</td>
                      <td className="px-3 py-3 font-semibold"><Cell v={r.tw} /></td>
                      <td className="px-3 py-3"><Cell v={r.abwrap} /></td>
                      <td className="px-3 py-3"><Cell v={r.bwrap} /></td>
                      <td className="px-3 py-3"><Cell v={r.pd} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="border-t border-line px-4 md:px-5 py-3 text-[10.5px] text-dim leading-relaxed">
              *bwrap evaluated as-if unprivileged namespaces were usable — on rooted or custom-kernel devices only.
              abwrap numbers reflect its published goal of bwrap-parity without a working namespace path on stock kernels.
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

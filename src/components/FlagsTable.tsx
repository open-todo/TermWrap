import { Reveal, SectionHead } from './ui';
import { FLAG_GROUPS } from '../lib/data';

export function FlagsTable() {
  return (
    <section id="flags" className="relative py-24 md:py-32">
      <div className="mx-auto max-w-6xl px-4 md:px-8">
        <SectionHead
          index="05"
          kicker="reference"
          title="TW(1) — FLAG REFERENCE"
          desc="The full surface. Everything below is implemented in the shipped termwrap.sh — same names as bubblewrap where they exist, honest machinery where they can't."
        />

        <div className="space-y-8">
          {FLAG_GROUPS.map((g, gi) => (
            <Reveal key={g.group} delay={gi * 0.05}>
              <div className="panel overflow-hidden">
                <div className="flex flex-wrap items-baseline justify-between gap-2 border-b border-line bg-panel2/70 px-4 md:px-5 py-3">
                  <div className="font-disp text-sm md:text-base font-semibold uppercase tracking-[0.18em] text-pho">
                    {g.group}
                  </div>
                  <div className="text-[10.5px] uppercase tracking-[0.18em] text-dim">{g.note}</div>
                </div>
                <div className="divide-y divide-line/70">
                  {g.rows.map((r) => (
                    <div
                      key={r.flag + (r.arg ?? '')}
                      className="group grid grid-cols-1 gap-1 px-4 md:px-5 py-3 md:grid-cols-[240px_1fr_auto] md:items-baseline md:gap-6 hover:bg-panel2/50 transition-colors"
                    >
                      <div className="text-[12.5px]">
                        <span className="text-pho font-semibold">{r.flag}</span>
                        {r.arg ? <span className="text-amber/80"> {r.arg}</span> : null}
                      </div>
                      <div className="text-[12px] leading-relaxed text-mist">{r.desc}</div>
                      <div className="text-[10px] uppercase tracking-[0.15em] text-fade md:text-right">
                        {r.equiv && r.equiv !== '—' ? <span>bwrap: {r.equiv}</span> : <span>tw-only</span>}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </Reveal>
          ))}
        </div>

        <Reveal delay={0.1}>
          <p className="mt-8 text-center text-[11px] uppercase tracking-[0.25em] text-dim">
            plus: <span className="text-pho">tw jail build|rebuild|discard|list|path</span> ·{' '}
            <span className="text-pho">--fresh-tmp</span> / <span className="text-pho">--share-tmp</span> ·{' '}
            <span className="text-pho">-0 / --no-fakeroot</span> · <span className="text-pho">--dry-run</span>
          </p>
        </Reveal>
      </div>
    </section>
  );
}

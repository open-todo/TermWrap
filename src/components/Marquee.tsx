import { MARQUEE } from '../lib/data';

export function Marquee({ flip = false }: { flip?: boolean }) {
  const row = [...MARQUEE, ...MARQUEE, ...MARQUEE];
  return (
    <div className="relative overflow-hidden border-y border-line bg-panel/60 py-3">
      <div className="animate-marquee flex w-max items-center gap-8" style={flip ? { animationDirection: 'reverse' } : undefined}>
        {row.map((m, i) => (
          <span key={i} className="flex items-center gap-8 whitespace-nowrap text-[11px] font-semibold tracking-[0.3em] text-dim">
            {m}
            <span className="text-pho">◆</span>
          </span>
        ))}
      </div>
      <div className="pointer-events-none absolute inset-y-0 left-0 w-24 bg-gradient-to-r from-ink to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 w-24 bg-gradient-to-l from-ink to-transparent" />
    </div>
  );
}

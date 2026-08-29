import { useEffect, useRef, useState, type ReactNode } from 'react';
import { motion, useInView } from 'framer-motion';
import { Check, Copy } from 'lucide-react';

// ---------------------------------------------------------------- Reveal
export function Reveal({
  children,
  delay = 0,
  y = 26,
  className = '',
}: {
  children: ReactNode;
  delay?: number;
  y?: number;
  className?: string;
}) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-70px' }}
      transition={{ duration: 0.7, delay, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </motion.div>
  );
}

// ---------------------------------------------------------------- Scramble
const GLYPHS = '!<>-_\\/[]{}—=+*^?#________';

export function Scramble({ text, className = '' }: { text: string; className?: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, margin: '-40px' });
  const [out, setOut] = useState(text);

  useEffect(() => {
    if (!inView) return;
    let frame = 0;
    const total = Math.max(14, text.length * 1.3);
    const id = window.setInterval(() => {
      frame++;
      const done = Math.floor((frame / total) * text.length);
      let s = '';
      for (let i = 0; i < text.length; i++) {
        if (i < done || text[i] === ' ') s += text[i];
        else s += GLYPHS[Math.floor(Math.random() * GLYPHS.length)];
      }
      setOut(s);
      if (done >= text.length) {
        setOut(text);
        window.clearInterval(id);
      }
    }, 34);
    return () => window.clearInterval(id);
  }, [inView, text]);

  return (
    <span ref={ref} className={className}>
      {out}
    </span>
  );
}

// ---------------------------------------------------------------- SectionHead
export function SectionHead({
  index,
  kicker,
  title,
  desc,
}: {
  index: string;
  kicker: string;
  title: string;
  desc?: string;
}) {
  return (
    <div className="mb-12 md:mb-16">
      <Reveal>
        <div className="flex items-center gap-3 mb-5">
          <span className="text-pho text-[11px] tracking-[0.3em]">[{index}]</span>
          <span className="kicker text-dim">{kicker}</span>
          <span className="h-px flex-1 bg-line" />
        </div>
      </Reveal>
      <Reveal delay={0.08}>
        <h2 className="font-disp text-3xl md:text-5xl font-bold tracking-tight text-[#e6f4e6]">
          <Scramble text={title} />
        </h2>
      </Reveal>
      {desc && (
        <Reveal delay={0.16}>
          <p className="mt-4 max-w-2xl text-sm md:text-[15px] leading-relaxed text-mist">{desc}</p>
        </Reveal>
      )}
    </div>
  );
}

// ---------------------------------------------------------------- Chip
export function Chip({ children, tone = 'dim' }: { children: ReactNode; tone?: 'dim' | 'pho' | 'amber' }) {
  const map = {
    dim: 'border-line text-mist',
    pho: 'border-pho/40 text-pho',
    amber: 'border-amber/40 text-amber',
  } as const;
  return (
    <span
      className={`inline-flex items-center gap-1.5 border px-2.5 py-1 text-[10px] tracking-[0.14em] uppercase bg-ink/60 ${map[tone]}`}
    >
      {children}
    </span>
  );
}

// ---------------------------------------------------------------- CopyButton
export function CopyButton({ text, label = 'copy', className = '' }: { text: string; label?: string; className?: string }) {
  const [done, setDone] = useState(false);
  return (
    <button
      onClick={() => {
        navigator.clipboard?.writeText(text).catch(() => {});
        setDone(true);
        window.setTimeout(() => setDone(false), 1600);
      }}
      className={`group inline-flex items-center gap-2 border border-line bg-ink/70 px-3 py-2 text-[11px] uppercase tracking-[0.18em] text-mist transition-colors hover:border-pho/50 hover:text-pho ${className}`}
    >
      {done ? <Check size={13} className="text-pho" /> : <Copy size={13} className="transition-transform group-hover:-translate-y-px" />}
      {done ? 'copied' : label}
    </button>
  );
}

// ---------------------------------------------------------------- TermWindow chrome
export function TermChrome({
  title,
  right,
}: {
  title: string;
  right?: ReactNode;
}) {
  return (
    <div className="flex items-center justify-between border-b border-line bg-[#0c110c] px-4 py-2.5">
      <div className="flex items-center gap-2">
        <span className="h-2.5 w-2.5 rounded-full bg-blood/70" />
        <span className="h-2.5 w-2.5 rounded-full bg-amber/70" />
        <span className="h-2.5 w-2.5 rounded-full bg-pho/70" />
      </div>
      <div className="text-[10px] tracking-[0.25em] uppercase text-dim">{title}</div>
      <div className="flex items-center gap-2 min-w-[52px] justify-end">{right}</div>
    </div>
  );
}

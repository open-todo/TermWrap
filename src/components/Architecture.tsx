import { MousePointer2 } from 'lucide-react';
import { Reveal, SectionHead } from './ui';

function Node({
  x,
  y,
  w,
  h,
  title,
  sub,
  tone = 'pho',
  dash = false,
}: {
  x: number; y: number; w: number; h: number;
  title: string; sub?: string; tone?: 'pho' | 'blood' | 'amber' | 'dim' | 'ice';
  dash?: boolean;
}) {
  const stroke =
    tone === 'blood' ? '#ff6159' : tone === 'amber' ? '#ffb224' : tone === 'dim' ? '#33402f' : tone === 'ice' ? '#58d6e0' : '#79ff8f';
  return (
    <g>
      <rect
        x={x} y={y} width={w} height={h} rx={3}
        fill={tone === 'dim' ? 'rgba(13,19,13,0.9)' : 'rgba(10,14,10,0.95)'}
        stroke={stroke} strokeOpacity={tone === 'dim' ? 0.9 : 0.55}
        strokeDasharray={dash ? '5 5' : undefined}
      />
      <rect x={x} y={y} width={w} height={18} rx={3} fill={stroke} fillOpacity={tone === 'dim' ? 0.06 : 0.1} />
      <text x={x + 10} y={y + 13} fontSize={10} fill={stroke} fontFamily="JetBrains Mono, monospace" fontWeight={700}>
        {title}
      </text>
      {sub && (
        <text x={x + 10} y={y + 34} fontSize={9.5} fill="#93ad93" fontFamily="JetBrains Mono, monospace">
          {sub}
        </text>
      )}
    </g>
  );
}

function Flow({ d, tone = 'pho', label, lx, ly }: { d: string; tone?: 'pho' | 'amber' | 'blood' | 'dim' | 'ice'; label?: string; lx?: number; ly?: number }) {
  const stroke = tone === 'blood' ? '#ff6159' : tone === 'amber' ? '#ffb224' : tone === 'ice' ? '#58d6e0' : tone === 'dim' ? '#4c5c4d' : '#79ff8f';
  return (
    <g>
      <path d={d} fill="none" stroke={stroke} strokeOpacity={0.18} strokeWidth={7} strokeLinecap="round" />
      <path d={d} fill="none" stroke={stroke} strokeOpacity={0.8} strokeWidth={1.4} className="flow-dash" />
      {label && (
        <text x={lx} y={ly} fontSize={9} fill={stroke} fontFamily="JetBrains Mono, monospace" textAnchor="middle">
          {label}
        </text>
      )}
    </g>
  );
}

const STEPS = [
  { n: '01', t: 'agent calls open("/home/you/.ssh/id")', d: 'libc issues the syscall as usual — the process does not know it is traced.' },
  { n: '02', t: 'proot PTRACE_SYSCALL stop', d: 'the tracer wakes, inspects the syscall table and argument pointer.' },
  { n: '03', t: 'path rewrite → scratch view', d: '.ssh is bound to an empty dir: the string in the guest’s register memory is rewritten.' },
  { n: '04', t: 'kernel answers ENOENT', d: 'secret was never at the rewritten address. existence denied, not permission denied.' },
];

export function Architecture() {
  return (
    <section id="arch" className="relative py-24 md:py-32">
      <div className="mx-auto max-w-7xl px-4 md:px-8">
        <SectionHead
          index="03"
          kicker="mechanics"
          title="ISOLATION WITHOUT NAMESPACES"
          desc="ptrace lets one process stop another at every syscall boundary and edit its arguments. termwrap spends that superpower on exactly three things: what you can see, how far you can talk, and how much you may burn."
        />

        <Reveal>
          <div className="panel term-shadow relative overflow-hidden">
            <div className="flex items-center justify-between border-b border-line px-4 py-2.5 text-[10px] uppercase tracking-[0.25em] text-dim">
              <span>fig. 1 — the tw pipeline</span>
              <span className="flex items-center gap-2 text-pho">
                <MousePointer2 size={11} /> ptrace stops: every syscall
              </span>
            </div>
            <div className="overflow-x-auto">
              <svg viewBox="0 0 940 520" className="min-w-[760px] w-full" role="img" aria-label="termwrap architecture diagram">
                {/* zones */}
                <rect x={18} y={18} width={430} height={400} fill="none" stroke="#33402f" strokeDasharray="3 6" />
                <text x={30} y={40} fontSize={10} fill="#576b58" fontFamily="JetBrains Mono, monospace">HOST REALITY — your actual device</text>
                <rect x={500} y={18} width={422} height={400} fill="none" stroke="#33402f" strokeDasharray="3 6" />
                <text x={512} y={40} fontSize={10} fill="#576b58" fontFamily="JetBrains Mono, monospace">GUEST ILLUSION — what the agent experiences</text>

                {/* host nodes */}
                <Node x={40} y={70} w={180} h={52} title="tw (bash)" sub="flags → policy → cages" />
                <Node x={40} y={160} w={180} h={52} title="jail /tmp /scratches" sub="tar snapshot + tmp dirs" tone="dim" />
                <Node x={250} y={70} w={176} h={52} title="netblock.so" sub="LD_PRELOAD socket()" tone="amber" />
                <Node x={250} y={160} w={176} h={52} title="audit.log" sub="execve + rewrites" tone="ice" />
                <Node x={40} y={250} w={386} h={52} title="ulimit + timeout cage" sub="procs · fds · mem · fuse --kill-on-exit" tone="dim" />
                <Node x={40} y={340} w={386} h={58} title="stock android kernel" sub="CONFIG_USER_NS=n · SELinux enforcing — untouched" tone="dim" />

                {/* tracer spine */}
                <Node x={470} y={70} w={120} h={240} title="proot" dash />
                <text x={530} y={180} fontSize={9.5} fill="#79ff8f" fontFamily="JetBrains Mono, monospace" textAnchor="middle" transform="rotate(-90 530 180)">
                  ptrace(2) — rewrite on every stop
                </text>

                {/* guest nodes */}
                <Node x={640} y={70} w={260} h={52} title="agent process" sub="python/node/bash — none the wiser" tone="blood" />
                <Node x={640} y={160} w={260} h={52} title="bionic libc" sub="socket() → shim → EACCES" tone="amber" />
                <Node x={640} y={250} w={260} h={52} title="fake filesystem view" sub="~ = scratch · .ssh = ∅ · /usr = jail" tone="ice" />
                <Node x={640} y={340} w={260} h={58} title="network" sub="deny by policy · attempts logged" tone="blood" dash />

                {/* flows */}
                <Flow d="M 130 122 C 130 210 530 40 530 68" label="exec under trace" lx={300} ly={62} />
                <Flow d="M 590 96 L 640 96" label="spawns" lx={615} ly={88} />
                <Flow d="M 770 122 L 770 156" tone="amber" label="dials" lx={770} ly={144} />
                <Flow d="M 770 212 L 770 246" tone="dim" label="opens" lx={770} ly={236} />
                <Flow d="M 770 302 L 770 336" tone="blood" label="blocked" lx={770} ly={326} />
                <Flow d="M 530 310 C 530 430 220 420 130 400" tone="dim" label="syscalls" lx={330} ly={436} />
                <Flow d="M 470 186 L 426 186" tone="ice" label="trace → log" lx={448} ly={176} />

                {/* side notes */}
                <text x={40} y={430} fontSize={9.5} fill="#576b58" fontFamily="JetBrains Mono, monospace">
                  * no kernel feature is relied on beyond ptrace between same-uid processes —
                </text>
                <text x={40} y={444} fontSize={9.5} fill="#576b58" fontFamily="JetBrains Mono, monospace">
                  the one thing Android has always allowed. that is the whole trick.
                </text>
              </svg>
            </div>
          </div>
        </Reveal>

        {/* anatomy of a syscall */}
        <div className="mt-10 grid gap-px border border-line bg-line md:grid-cols-4">
          {STEPS.map((s, i) => (
            <Reveal key={s.n} delay={i * 0.08} className="bg-panel px-5 py-6">
              <div className="text-[10px] tracking-[0.3em] text-pho mb-3">{s.n}</div>
              <div className="font-disp text-[15px] font-semibold text-[#e6f4e6] leading-snug">{s.t}</div>
              <p className="mt-3 text-[12px] leading-relaxed text-mist">{s.d}</p>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

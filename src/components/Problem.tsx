import { motion } from 'framer-motion';
import { XCircle, CheckCircle2, Lock, Package, Radar, ArrowRight } from 'lucide-react';
import { Reveal, SectionHead, TermChrome } from './ui';

const CARDS = [
  {
    icon: Lock,
    mark: 'unavailable',
    tone: 'blood' as const,
    title: 'user namespaces',
    body: 'bwrap unshares user+mount namespaces. Android kernels ship CONFIG_USER_NS off or wedged behind SELinux — unprivileged creation returns EPERM. This is why abwrap dies at "setting up uid map: Permission denied".',
  },
  {
    icon: Package,
    mark: 'unavailable',
    tone: 'blood' as const,
    title: 'suid / root helpers',
    body: 'No root, no setuid, no install-time capabilities on /data. Any tool whose isolation plan starts with "as root…" is dead on arrival on stock devices.',
  },
  {
    icon: Radar,
    mark: 'available',
    tone: 'pho' as const,
    title: 'ptrace(2) — same uid',
    body: 'Tracing your own processes is completely legal on Android. proot exploits this to intercept every syscall and rewrite paths on the fly. proot-distro has run entire distributions on it for years. termwrap weaponizes it for isolation.',
  },
];

export function Problem() {
  return (
    <section id="problem" className="relative py-24 md:py-32">
      <div className="mx-auto max-w-7xl px-4 md:px-8">
        <SectionHead
          index="01"
          kicker="the wall"
          title="BUBBLEWRAP CAN'T SAVE YOU HERE"
          desc="On desktop Linux, bwrap is perfect. On stock Android it never even starts — the isolation primitives it needs are compiled out of the kernel. So we change primitives, not goals."
        />

        <div className="grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
          {/* failing bwrap */}
          <Reveal className="lg:sticky lg:top-24 self-start">
            <div className="panel term-shadow">
              <TermChrome
                title="repro — any stock device"
                right={<span className="text-[9px] uppercase tracking-[0.2em] text-blood">exit 1</span>}
              />
              <div className="px-4 md:px-5 py-5 text-[11.5px] md:text-[12.5px] leading-[1.8]">
                <div className="tl-dim">$ <span className="text-[#d9f8dd]">pkg install bubblewrap</span></div>
                <div className="tl-dim">$ <span className="text-[#d9f8dd]">bwrap --dev-bind / / --unshare-net echo hi</span></div>
                <div className="tl-err">bwrap: setting up uid map: Permission denied</div>
                <div className="tl-dim mt-3">$ <span className="text-[#d9f8dd]">abwrap --isolated bash</span></div>
                <div className="tl-err">abwrap: unshare(CLONE_NEWUSER): Operation not permitted</div>
                <div className="mt-4 h-px bg-line" />
                <div className="tl-dim mt-4">$ <span className="text-[#d9f8dd]">tw --hide ~/.ssh --unshare-net -- echo hello</span></div>
                <div className="tl-ok">[ok] scratch home · hidden: ~/.ssh · net BLOCKED</div>
                <div className="tl-ok">[ok] fake uid 0 · audit on</div>
                <div className="text-[#d9f8dd]">hello</div>
                <div className="tl-ok">[ok] sandbox torn down · exit 0 · host untouched</div>
              </div>
            </div>
          </Reveal>

          {/* cause cards */}
          <div className="space-y-5">
            {CARDS.map((c, i) => (
              <motion.div
                key={c.title}
                initial={{ opacity: 0, x: 30 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, margin: '-60px' }}
                transition={{ duration: 0.6, delay: i * 0.1 }}
                className="panel group relative overflow-hidden px-5 py-5 md:px-7"
              >
                <div
                  className={`absolute left-0 top-0 h-full w-[3px] ${c.tone === 'blood' ? 'bg-blood/60' : 'bg-pho/70'}`}
                />
                <div className="flex items-start justify-between gap-4">
                  <div className="flex items-center gap-3">
                    <c.icon size={19} className={c.tone === 'blood' ? 'text-blood' : 'text-pho'} />
                    <h3 className="font-disp text-lg md:text-xl font-semibold text-[#e6f4e6]">{c.title}</h3>
                  </div>
                  <span
                    className={`inline-flex shrink-0 items-center gap-1.5 text-[9px] md:text-[10px] uppercase tracking-[0.2em] ${
                      c.tone === 'blood' ? 'text-blood' : 'text-pho'
                    }`}
                  >
                    {c.tone === 'blood' ? <XCircle size={12} /> : <CheckCircle2 size={12} />}
                    {c.mark}
                  </span>
                </div>
                <p className="mt-3 text-[12.5px] md:text-[13.5px] leading-relaxed text-mist">{c.body}</p>
              </motion.div>
            ))}

            <Reveal delay={0.25}>
              <a
                href="#arch"
                className="group mt-2 flex items-center justify-between border border-pho/30 bg-pho/5 px-5 py-4 text-[11px] md:text-xs uppercase tracking-[0.22em] text-pho transition-colors hover:bg-pho hover:text-ink"
              >
                <span>see the ptrace machinery</span>
                <ArrowRight size={15} className="transition-transform group-hover:translate-x-1.5" />
              </a>
            </Reveal>
          </div>
        </div>
      </div>
    </section>
  );
}

import { motion } from 'framer-motion';
import {
  EyeOff, Layers, Network, Recycle, Gauge, Timer, ScrollText, BookOpenCheck, Terminal,
} from 'lucide-react';
import { SectionHead } from './ui';
import { FEATURES } from '../lib/data';

const ICONS = { EyeOff, Layers, Network, Recycle, Gauge, Timer, ScrollText, BookOpenCheck, Terminal } as const;

export function Features() {
  return (
    <section id="features" className="relative py-24 md:py-32">
      <div className="mx-auto max-w-7xl px-4 md:px-8">
        <SectionHead
          index="04"
          kicker="capabilities"
          title="EVERY RAIL AN AGENT NEEDS TO HIT"
          desc="Each feature maps to one failure mode you have already watched an agent produce. Compose them with flags, or inherit them all with --profile ai-agent."
        />

        <div className="grid gap-px border border-line bg-line sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map((f, i) => {
            const Icon = ICONS[f.icon as keyof typeof ICONS];
            return (
              <motion.div
                key={f.title}
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-50px' }}
                transition={{ duration: 0.55, delay: (i % 3) * 0.08 }}
                className="group relative bg-panel px-6 py-7 transition-colors hover:bg-panel2"
              >
                <div className="absolute right-4 top-4 text-[9px] uppercase tracking-[0.18em] text-fade transition-colors group-hover:text-pho/70">
                  {f.tag}
                </div>
                <div className="mb-5 grid h-10 w-10 place-items-center border border-line bg-ink text-pho transition-all group-hover:border-pho/50 group-hover:shadow-[0_0_24px_-6px_rgba(121,255,143,0.5)]">
                  <Icon size={17} />
                </div>
                <h3 className="font-disp text-[17px] font-semibold text-[#e6f4e6]">{f.title}</h3>
                <p className="mt-3 text-[12.5px] leading-relaxed text-mist">{f.body}</p>
                <div className="mt-5 h-px w-full bg-line">
                  <div className="h-px w-0 bg-pho transition-all duration-500 group-hover:w-full" />
                </div>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

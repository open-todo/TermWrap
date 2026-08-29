import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Plus } from 'lucide-react';
import { SectionHead } from './ui';
import { FAQS } from '../lib/data';

export function Faq() {
  const [open, setOpen] = useState<number>(0);
  return (
    <section id="faq" className="relative py-24 md:py-32">
      <div className="mx-auto max-w-4xl px-4 md:px-8">
        <SectionHead index="10" kicker="interrogation" title="FREQUENTLY POKED QUESTIONS" />
        <div className="border border-line divide-y divide-line bg-panel">
          {FAQS.map((f, i) => {
            const isOpen = open === i;
            return (
              <div key={f.q}>
                <button
                  onClick={() => setOpen(isOpen ? -1 : i)}
                  className="flex w-full items-center justify-between gap-4 px-5 md:px-6 py-5 text-left group"
                >
                  <span className="flex items-center gap-4">
                    <span className={`text-[10px] tracking-[0.2em] ${isOpen ? 'text-pho' : 'text-fade'}`}>
                      {String(i + 1).padStart(2, '0')}
                    </span>
                    <span
                      className={`font-disp text-[15px] md:text-[17px] font-semibold transition-colors ${
                        isOpen ? 'text-pho' : 'text-[#e6f4e6] group-hover:text-pho2'
                      }`}
                    >
                      {f.q}
                    </span>
                  </span>
                  <motion.span animate={{ rotate: isOpen ? 45 : 0 }} transition={{ duration: 0.25 }}>
                    <Plus size={16} className={isOpen ? 'text-pho' : 'text-dim'} />
                  </motion.span>
                </button>
                <AnimatePresence initial={false}>
                  {isOpen && (
                    <motion.div
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.32, ease: [0.22, 1, 0.36, 1] }}
                      className="overflow-hidden"
                    >
                      <p className="px-5 md:px-6 pb-6 pl-[52px] md:pl-[56px] text-[12.5px] md:text-[13px] leading-relaxed text-mist max-w-3xl">
                        {f.a}
                      </p>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

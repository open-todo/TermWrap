import { useState } from 'react';
import { motion, useScroll, AnimatePresence } from 'framer-motion';
import { Menu, X, ArrowDownToLine, TerminalSquare } from 'lucide-react';

const LINKS = [
  ['problem', 'why'],
  ['demo', 'demo'],
  ['arch', 'how'],
  ['flags', 'flags'],
  ['playbook', 'playbook'],
  ['source', 'source'],
  ['security', 'security'],
  ['install', 'install'],
] as const;

export function Nav() {
  const { scrollYProgress } = useScroll();
  const [open, setOpen] = useState(false);

  return (
    <header className="fixed inset-x-0 top-0 z-[80]">
      <div className="border-b border-line bg-ink/85 backdrop-blur-md">
        <div className="mx-auto flex h-14 max-w-7xl items-center justify-between px-4 md:px-8">
          <a href="#top" className="group flex items-center gap-3">
            <span className="grid h-8 w-8 place-items-center border border-pho/40 bg-panel text-pho transition-colors group-hover:bg-pho group-hover:text-ink">
              <TerminalSquare size={15} />
            </span>
            <span className="text-sm font-bold tracking-[0.22em] text-[#e6f4e6]">
              TERMWRAP<span className="text-pho">_</span>
            </span>
            <span className="hidden text-[10px] tracking-[0.2em] text-dim sm:inline">v0.1.0</span>
          </a>

          <nav className="hidden items-center gap-6 lg:flex">
            {LINKS.map(([id, label]) => (
              <a
                key={id}
                href={`#${id}`}
                className="text-[11px] uppercase tracking-[0.2em] text-mist transition-colors hover:text-pho"
              >
                {label}
              </a>
            ))}
          </nav>

          <div className="flex items-center gap-3">
            <a
              href="#install"
              className="hidden border border-pho/40 bg-pho/10 px-4 py-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-pho transition-all hover:bg-pho hover:text-ink sm:block"
            >
              $ install
            </a>
            <button
              onClick={() => setOpen((v) => !v)}
              className="grid h-9 w-9 place-items-center border border-line text-mist lg:hidden"
              aria-label="menu"
            >
              {open ? <X size={16} /> : <Menu size={16} />}
            </button>
          </div>
        </div>
        <motion.div
          className="h-[2px] origin-left bg-gradient-to-r from-pho/80 via-pho to-ice/80"
          style={{ scaleX: scrollYProgress }}
        />
      </div>

      <AnimatePresence>
        {open && (
          <motion.nav
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.22 }}
            className="border-b border-line bg-ink/95 backdrop-blur-md lg:hidden"
          >
            <div className="grid grid-cols-2 gap-px bg-line">
              {LINKS.map(([id, label]) => (
                <a
                  key={id}
                  href={`#${id}`}
                  onClick={() => setOpen(false)}
                  className="flex items-center gap-2 bg-panel px-5 py-4 text-[12px] uppercase tracking-[0.2em] text-mist hover:text-pho"
                >
                  <span className="text-pho">▸</span> {label}
                </a>
              ))}
              <a
                href="#install"
                onClick={() => setOpen(false)}
                className="col-span-2 flex items-center justify-center gap-2 bg-pho px-5 py-4 text-[12px] font-bold uppercase tracking-[0.2em] text-ink"
              >
                <ArrowDownToLine size={14} /> install now
              </a>
            </div>
          </motion.nav>
        )}
      </AnimatePresence>
    </header>
  );
}

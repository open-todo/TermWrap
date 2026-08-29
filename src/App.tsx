import { Nav } from './components/Nav';
import { Hero } from './components/Hero';
import { Marquee } from './components/Marquee';
import { Problem } from './components/Problem';
import { TerminalDemo } from './components/TerminalDemo';
import { Architecture } from './components/Architecture';
import { Features } from './components/Features';
import { FlagsTable } from './components/FlagsTable';
import { Playbook } from './components/Playbook';
import { SourceBrowser } from './components/SourceBrowser';
import { Security } from './components/Security';
import { Install } from './components/Install';
import { Faq } from './components/Faq';
import { Footer } from './components/Footer';
import { Reveal, CopyButton } from './components/ui';
import { H_INSTALL_URL, siteOrigin } from './lib/data';

function BigCta() {
  const cmd = `curl -fsSL ${siteOrigin()}${H_INSTALL_URL} | bash`;
  return (
    <section className="relative overflow-hidden py-24 md:py-36 border-t border-line grid-bg">
      <div className="pointer-events-none absolute left-1/2 top-1/2 h-[300px] w-[600px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-pho/10 blur-[120px]" />
      <div className="relative mx-auto max-w-4xl px-4 text-center">
        <Reveal>
          <div className="kicker text-pho mb-6">// stop reading. start sandboxing.</div>
        </Reveal>
        <Reveal delay={0.1}>
          <h2 className="font-disp text-4xl md:text-6xl font-bold tracking-tight text-[#e6f4e6]">
            YOUR AGENT'S NEXT
            <br />
            <span className="text-pho text-glow">rm -rf</span> SHOULD BE
            <br />
            A <span className="text-pho text-glow">NON-EVENT.</span>
          </h2>
        </Reveal>
        <Reveal delay={0.2}>
          <div className="panel term-shadow mx-auto mt-10 flex max-w-xl flex-col sm:flex-row items-center gap-3 px-4 py-3">
            <code className="flex-1 truncate text-[12px] md:text-[13px] text-[#d9f8dd]">
              <span className="text-pho">$ </span>
              {cmd}
            </code>
            <CopyButton text={cmd} label="copy" />
          </div>
        </Reveal>
        <Reveal delay={0.3}>
          <p className="mt-6 text-[11px] uppercase tracking-[0.25em] text-dim">
            no root · no namespaces · no excuses
          </p>
        </Reveal>
      </div>
    </section>
  );
}

export default function App() {
  return (
    <div className="crt relative min-h-screen bg-ink font-mono">
      {/* global furniture */}
      <div className="noise" />
      <div className="scanbar" />

      <Nav />
      <main>
        <Hero />
        <Marquee />
        <Problem />
        <TerminalDemo />
        <Architecture />
        <Marquee flip />
        <Features />
        <FlagsTable />
        <Playbook />
        <SourceBrowser />
        <Security />
        <Install />
        <Faq />
        <BigCta />
      </main>
      <Footer />
    </div>
  );
}

import { useState } from 'react';
import { Bot, FileCheck2, Repeat2, Download } from 'lucide-react';
import { Reveal, SectionHead } from './ui';
import { CodeBlock, useFileSource } from './highlight';
import { ghRaw } from '../lib/data';

const STEPS = [
  {
    icon: Bot,
    t: 'loop 1 · propose',
    d: 'Your agent/LLM thinks on the host side where the API key and network live. It emits a plan: plain commands, one per line.',
  },
  {
    icon: FileCheck2,
    t: 'loop 2 · gate',
    d: 'agent-guard.sh shows each command, lets you y/N/edit it, then runs it through tw with the ai-agent policy. No human in the loop? pass -y and lean on the cage.',
  },
  {
    icon: Repeat2,
    t: 'loop 3 · audit & reset',
    d: 'Every execve and rewrite lands in the audit log, the sandbox self-destructs, and the next iteration starts from a sterile room.',
  },
];

export function Playbook() {
  const [tab, setTab] = useState<'profile' | 'guard'>('profile');
  const profile = useFileSource('/files/ai-agent.conf');
  const guard = useFileSource('/files/agent-guard.sh');

  const active = tab === 'profile'
    ? { data: profile.text, lang: 'conf' as const, name: 'ai-agent.conf', path: '/files/ai-agent.conf', raw: ghRaw('ai-agent.conf') }
    : { data: guard.text, lang: 'bash' as const, name: 'agent-guard.sh', path: '/files/agent-guard.sh', raw: ghRaw('agent-guard.sh') };

  return (
    <section id="playbook" className="relative py-24 md:py-32">
      <div className="mx-auto max-w-6xl px-4 md:px-8">
        <SectionHead
          index="06"
          kicker="field manual"
          title="THE AGENT PLAYBOOK"
          desc="The pattern that makes autonomous agents boring instead of terrifying: the model proposes on the network, the sandbox disposes off it. Ship the policy once, gate every action, audit everything."
        />

        {/* 3-step loop */}
        <div className="mb-10 grid gap-px border border-line bg-line md:grid-cols-3">
          {STEPS.map((s, i) => (
            <Reveal key={s.t} delay={i * 0.08} className="bg-panel px-6 py-6">
              <s.icon size={18} className="text-pho mb-4" />
              <div className="text-[10px] uppercase tracking-[0.3em] text-pho mb-2">{s.t}</div>
              <p className="text-[12.5px] leading-relaxed text-mist">{s.d}</p>
            </Reveal>
          ))}
        </div>

        {/* two-phase snippet */}
        <Reveal>
          <div className="panel mb-10 px-5 py-4">
            <div className="text-[10px] uppercase tracking-[0.25em] text-dim mb-3">two-phase wiring — 20 seconds of setup:</div>
            <pre className="overflow-x-auto text-[12px] md:text-[13px] leading-[1.8]">
              <code>
                <span className="text-fade"># ① one-time policy + jail</span>{'\n'}
                <span className="text-pho">$</span> tw jail build stock{'\n'}
                <span className="text-fade"># ② pipe any planner into the guard</span>{'\n'}
                <span className="text-pho">$</span> llm <span className="text-[#ffcf87]">"shell plan to set up this repo"</span> | ./agent-guard.sh{'\n'}
                <span className="text-fade"># ③ or wrap your own agent loop</span>{'\n'}
                <span className="text-pho">$</span> tw --profile ai-agent --jail stock -- python3 my_agent.py{'\n'}
                <span className="text-fade"># mcp runtimes too: wrap the server process itself</span>{'\n'}
                <span className="text-pho">$</span> tw --profile ai-agent -- npx -y @modelcontextprotocol/server-filesystem .
              </code>
            </pre>
          </div>
        </Reveal>

        {/* source tabs */}
        <Reveal delay={0.05}>
          <div>
            <div className="flex flex-wrap items-center gap-px border border-b-0 border-line bg-line">
              {(['profile', 'guard'] as const).map((t) => (
                <button
                  key={t}
                  onClick={() => setTab(t)}
                  className={`px-5 py-3 text-[11px] uppercase tracking-[0.2em] transition-colors ${
                    tab === t ? 'bg-panel2 text-pho' : 'bg-panel text-dim hover:text-mist'
                  }`}
                >
                  {t === 'profile' ? 'ai-agent.conf' : 'agent-guard.sh'}
                </button>
              ))}
              <a
                href={active.raw}
                download
                className="ml-auto flex items-center gap-2 px-5 py-3 text-[11px] uppercase tracking-[0.2em] text-mist hover:text-pho bg-panel"
              >
                <Download size={12} /> {active.name}
              </a>
            </div>
            {active.data ? (
              <CodeBlock code={active.data} lang={active.lang} maxH="max-h-[430px]" />
            ) : (
              <div className="panel-flat px-5 py-8 text-[12px] text-dim">loading {active.name} …</div>
            )}
          </div>
        </Reveal>
      </div>
    </section>
  );
}

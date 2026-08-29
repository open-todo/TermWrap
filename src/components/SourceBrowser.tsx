import { useState } from 'react';
import { Download, FileCode2, AlertTriangle } from 'lucide-react';
import { SectionHead, CopyButton } from './ui';
import { CodeBlock, useFileSource } from './highlight';
import { FILES_META } from '../lib/data';

export function SourceBrowser() {
  const [idx, setIdx] = useState(0);
  const meta = FILES_META[idx];
  const { text } = useFileSource(meta.path);

  return (
    <section id="source" className="relative py-24 md:py-32">
      <div className="mx-auto max-w-6xl px-4 md:px-8">
        <SectionHead
          index="07"
          kicker="read the source, luke"
          title="ONE SHELL SCRIPT, ZERO MAGIC"
          desc="No binary blobs, no opaque daemons. Every file below is served raw from this site — audit them, then pipe the installer with a clear conscience."
        />

        <div className="grid gap-6 lg:grid-cols-[240px_1fr]">
          {/* file list */}
          <div className="flex lg:flex-col gap-px border border-line bg-line self-start overflow-x-auto lg:overflow-visible">
            {FILES_META.map((f, i) => (
              <button
                key={f.name}
                onClick={() => setIdx(i)}
                className={`flex items-center gap-3 px-4 py-3.5 text-left transition-colors min-w-[200px] ${
                  i === idx ? 'bg-panel2 text-pho' : 'bg-panel text-dim hover:text-mist'
                }`}
              >
                <FileCode2 size={14} className="shrink-0" />
                <span className="text-[12px] font-semibold">{f.name}</span>
              </button>
            ))}
          </div>

          {/* file view */}
          <div className="min-w-0">
            <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
              <div className="text-[11px] uppercase tracking-[0.2em] text-dim">{meta.role}</div>
              <div className="flex items-center gap-2">
                <CopyButton text={text ?? ''} label="copy raw" />
                <a
                  href={meta.raw}
                  download
                  className="inline-flex items-center gap-2 border border-pho/40 bg-pho/10 px-3 py-2 text-[11px] uppercase tracking-[0.18em] text-pho hover:bg-pho hover:text-ink transition-colors"
                >
                  <Download size={12} /> download
                </a>
              </div>
            </div>
            {text ? (
              <CodeBlock code={text} lang={meta.lang === 'conf' ? 'conf' : meta.lang} title={meta.name} maxH="max-h-[560px]" />
            ) : (
              <div className="panel-flat px-5 py-8 text-[12px] text-dim">
                <span className="inline-flex items-center gap-2">
                  <AlertTriangle size={13} className="text-amber" /> fetching {meta.path} …
                </span>
              </div>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}

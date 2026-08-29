import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { CopyButton } from './ui';

// Tiny hand-rolled highlighter — enough for bash / c / conf showcase code.
type Tok = { s: string; c?: string };

const C = {
  cmt: 'text-[#4c5c4d] italic',
  str: 'text-[#ffcf87]',
  flag: 'text-[#58d6e0]',
  kw: 'text-[#79ff8f]',
  num: 'text-[#ffb224]',
  var: 'text-[#e58fff]',
  pre: 'text-[#58d6e0]',
  fn: 'text-[#a8ffb6]',
  path: 'text-[#93ad93]',
};

function tokenizeBash(line: string): Tok[] {
  const re =
    /(#[^\n]*)|("(?:[^"\\]|\\.)*")|('(?:[^'\\]|\\.)*')|(\b(?:if|then|else|elif|fi|for|while|until|do|done|case|esac|in|function|local|return|exit|readonly|export|shift|trap|set|source|eval|exec|echo|printf|cat|chmod|mkdir|cp|rm|install|curl|tar|cc|timeout|proot|env|nice|kill|wait|read|command)\b)|(--?[a-zA-Z][a-zA-Z0-9-]*)|(\$\{[^}]*\}|\$[\w@#?]+)|(\b\d+\b)|(~[\w\/.\-]*|\/[\w\/.\-]+)/g;
  return runRe(line, re, [C.cmt, C.str, C.str, C.kw, C.flag, C.var, C.num, C.path]);
}

function tokenizeC(line: string): Tok[] {
  const re =
    /(#\s*\w+[^\n]*)|(\/\/[^\n]*)|("(?:[^"\\]|\\.)*")|('(?:[^'\\]|\\.)*')|(\b(?:static|int|void|char|const|return|if|else|sizeof|typedef|struct|enum|unsigned|signed|long|short|for|while|do|break|continue|extern|volatile)\b)|(\b\d+\b)|([a-zA-Z_]\w*)(?=\s*\()/g;
  return runRe(line, re, [C.pre, C.cmt, C.str, C.str, C.kw, C.num, C.fn]);
}

function tokenizeConf(line: string): Tok[] {
  const re = /(#[^\n]*)|(--?[a-zA-Z][a-zA-Z0-9-]*)|(\$\{[^}]*\}|\$[\w@#?]+)|(~[\w\/.\-]*|\/[\w\/.\-]+)/g;
  return runRe(line, re, [C.cmt, C.flag, C.var, C.path]);
}

function runRe(line: string, re: RegExp, classes: (string | undefined)[]): Tok[] {
  const out: Tok[] = [];
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(line))) {
    if (m.index > last) out.push({ s: line.slice(last, m.index) });
    let cls: string | undefined;
    for (let g = 1; g < m.length; g++) {
      if (m[g] !== undefined) {
        cls = classes[g - 1];
        break;
      }
    }
    out.push({ s: m[0], c: cls });
    last = m.index + m[0].length;
  }
  if (last < line.length) out.push({ s: line.slice(last) });
  return out;
}

export function tokenize(line: string, lang: 'bash' | 'c' | 'conf' | 'plain'): Tok[] {
  if (lang === 'bash') return tokenizeBash(line);
  if (lang === 'c') return tokenizeC(line);
  if (lang === 'conf') return tokenizeConf(line);
  return [{ s: line }];
}

export function HLine({ line, lang }: { line: string; lang: 'bash' | 'c' | 'conf' | 'plain' }) {
  const toks = useMemo(() => tokenize(line, lang), [line, lang]);
  return (
    <>
      {toks.map((t, i) => (
        <span key={i} className={t.c}>
          {t.s}
        </span>
      ))}
    </>
  );
}

// --------------------------------------------------------------------------
export function CodeBlock({
  code,
  lang,
  title,
  footer,
  maxH = 'max-h-[460px]',
  copyText,
}: {
  code: string;
  lang: 'bash' | 'c' | 'conf' | 'plain';
  title?: string;
  footer?: ReactNode;
  maxH?: string;
  copyText?: string;
}) {
  const lines = code.replace(/\n$/, '').split('\n');
  return (
    <div className="panel-flat overflow-hidden">
      {title && (
        <div className="flex items-center justify-between border-b border-line px-4 py-2.5">
          <div className="flex items-center gap-2.5">
            <span className="h-1.5 w-1.5 rounded-full bg-pho animate-pulse" />
            <span className="text-[10px] tracking-[0.25em] uppercase text-mist">{title}</span>
          </div>
          <CopyButton text={copyText ?? code} />
        </div>
      )}
      <div className={`overflow-auto ${maxH} term-scroll`}>
        <pre className="px-4 py-4 text-[12px] md:text-[12.5px] leading-[1.7]">
          {lines.map((l, i) => (
            <div key={i} className="grid grid-cols-[2.4rem_1fr] gap-3">
              <span className="text-right text-fade select-none">{i + 1}</span>
              <span className="text-[#c9dcc9] whitespace-pre-wrap break-all">
                <HLine line={l} lang={lang} />
              </span>
            </div>
          ))}
        </pre>
      </div>
      {footer && <div className="border-t border-line px-4 py-2.5 text-[11px] text-dim">{footer}</div>}
    </div>
  );
}

// fetch source text served from /public/files
export function useFileSource(path: string) {
  const [text, setText] = useState<string | null>(null);
  const [err, setErr] = useState(false);
  useEffect(() => {
    let live = true;
    fetch(path)
      .then((r) => (r.ok ? r.text() : Promise.reject(r.status)))
      .then((t) => live && setText(t))
      .catch(() => live && setErr(true));
    return () => {
      live = false;
    };
  }, [path]);
  return { text, err };
}

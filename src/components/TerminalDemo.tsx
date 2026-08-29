import { useCallback, useEffect, useRef, useState } from 'react';
import { Play, Pause, RotateCcw, SkipForward } from 'lucide-react';
import { SectionHead, TermChrome, CopyButton } from './ui';
import { SCENES, type Scene } from '../lib/data';

type RL = { k: string; t: string };

export function TerminalDemo() {
  const [sceneIdx, setSceneIdx] = useState(0);
  const [session, setSession] = useState(0);
  const [rendered, setRendered] = useState<RL[]>([]);
  const [typed, setTyped] = useState('');
  const [playing, setPlaying] = useState(true);
  const [done, setDone] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  const st = useRef({
    li: 0,
    ch: 0,
    timer: 0,
    playing: true,
  });

  const scene: Scene = SCENES[sceneIdx];
  const total = scene.lines.length;

  const reset = useCallback((idx: number, autoplay = true) => {
    window.clearTimeout(st.current.timer);
    st.current.li = 0;
    st.current.ch = 0;
    st.current.playing = autoplay;
    setSceneIdx(idx);
    setRendered([]);
    setTyped('');
    setDone(false);
    setPlaying(autoplay);
    setSession((s) => s + 1);
  }, []);

  useEffect(() => {
    let alive = true;

    const tick = () => {
      if (!alive) return;
      const s = st.current;
      if (!s.playing) return;
      const sc = SCENES[sceneIdx];

      if (s.li >= sc.lines.length) {
        setDone(true);
        // auto-advance to next scene
        s.timer = window.setTimeout(() => {
          if (alive && s.playing) resetRef.current((sceneIdx + 1) % SCENES.length, true);
        }, 5200);
        return;
      }

      const line = sc.lines[s.li];
      const isCmd = line.k === 'cmd';
      const speed = isCmd ? 26 : 0;

      if (!isCmd) {
        // output appears as a beat
        setRendered((p) => [...p, { k: line.k, t: line.t }]);
        s.li++;
        const pause = line.k === 'sys' ? 520 : line.k === 'dim' ? 190 : 330;
        s.timer = window.setTimeout(tick, pause);
        return;
      }

      s.ch++;
      if (s.ch >= line.t.length) {
        setRendered((p) => [...p, { k: line.k, t: line.t }]);
        setTyped('');
        s.ch = 0;
        s.li++;
        s.timer = window.setTimeout(tick, 640);
        return;
      }
      setTyped(line.t.slice(0, s.ch));
      s.timer = window.setTimeout(tick, speed + Math.random() * 26);
    };

    st.current.timer = window.setTimeout(tick, 350);
    return () => {
      alive = false;
      window.clearTimeout(st.current.timer);
    };
    // session bumps restart the loop after pause/replay of the same scene
  }, [sceneIdx, session]);

  const resetRef = useRef(reset);
  resetRef.current = reset;

  // autoscroll
  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [rendered, typed]);

  const toggle = () => {
    st.current.playing = !st.current.playing;
    setPlaying(st.current.playing);
    if (!st.current.playing) {
      window.clearTimeout(st.current.timer);
    } else if (!done) {
      // restart the loop via a fresh effect session
      setSession((s) => s + 1);
    }
  };

  const next = () => resetRef.current((sceneIdx + 1) % SCENES.length, playing || done);

  const transcript = scene.lines.map((l) => (l.k === 'cmd' ? '$ ' + l.t : l.t)).join('\n');

  return (
    <section id="demo" className="relative py-24 md:py-32">
      <div className="pointer-events-none absolute left-1/2 top-0 h-px w-2/3 -translate-x-1/2 bg-gradient-to-r from-transparent via-line2 to-transparent" />
      <div className="mx-auto max-w-5xl px-4 md:px-8">
        <SectionHead
          index="02"
          kicker="live fire exercise"
          title="WATCH AN AGENT GET CAGED"
          desc="Three recorded runs, replayed keystroke-for-keystroke. Every block you see is a real behaviour of the shipped script — hidden paths, LD_PRELOAD net denial, jail-scoped rm -rf, systrace audits."
        />

        {/* tabs */}
        <div className="mb-0 flex flex-wrap gap-px border border-line bg-line">
          {SCENES.map((s, i) => (
            <button
              key={s.id}
              onClick={() => resetRef.current(i, true)}
              className={`group flex-1 min-w-[140px] px-4 py-3.5 text-left transition-colors ${
                i === sceneIdx ? 'bg-panel2 text-pho' : 'bg-panel text-dim hover:text-mist'
              }`}
            >
              <div className="text-[11px] md:text-xs font-semibold tracking-[0.12em] uppercase">{s.label}</div>
              <div className="mt-1 hidden md:block text-[10.5px] leading-snug text-dim group-hover:text-mist line-clamp-2">
                {s.blurb}
              </div>
            </button>
          ))}
        </div>

        {/* terminal */}
        <div className="panel term-shadow border-t-0">
          <TermChrome
            title={`tty0 — ${scene.label}`}
            right={
              <div className="flex items-center gap-1.5">
                <button
                  onClick={toggle}
                  className="grid h-6 w-6 place-items-center border border-line text-mist hover:text-pho hover:border-pho/50"
                  aria-label={playing ? 'pause' : 'play'}
                >
                  {playing ? <Pause size={11} /> : <Play size={11} />}
                </button>
                <button
                  onClick={() => resetRef.current(sceneIdx, true)}
                  className="grid h-6 w-6 place-items-center border border-line text-mist hover:text-pho hover:border-pho/50"
                  aria-label="replay"
                >
                  <RotateCcw size={11} />
                </button>
                <button
                  onClick={next}
                  className="grid h-6 w-6 place-items-center border border-line text-mist hover:text-pho hover:border-pho/50"
                  aria-label="next scene"
                >
                  <SkipForward size={11} />
                </button>
              </div>
            }
          />
          <div
            ref={scrollRef}
            className="h-[380px] md:h-[430px] overflow-y-auto px-4 md:px-5 py-4 text-[10.5px] sm:text-[11.5px] md:text-[12.5px] leading-[1.75]"
          >
            {rendered.map((l, i) => (
              <div key={i} className={`tl-${l.k} break-words whitespace-pre-wrap`}>
                {l.k === 'cmd' && !l.t.startsWith('[') ? <span className="text-fade">~ $ </span> : null}
                {l.t}
              </div>
            ))}
            {!done && (
              <div className="tl-cmd">
                {scene.lines[st.current.li]?.k === 'cmd' && !typed.startsWith('[') && (
                  <span className="text-fade">~ $ </span>
                )}
                {typed}
                <span className="caret ml-0.5 inline-block h-[12px] w-[7px] translate-y-[2px] bg-pho" />
              </div>
            )}
            {done && (
              <div className="mt-3 flex items-center gap-2 text-[10px] uppercase tracking-[0.25em]">
                <span className="text-pho">■ scene complete</span>
                <span className="text-fade">— auto-advancing…</span>
              </div>
            )}
          </div>
          {/* progress */}
          <div className="border-t border-line">
            <div
              className="h-[3px] transition-[width] duration-300"
              style={{
                width: `${Math.min(100, ((rendered.length + (typed ? 0.5 : 0)) / total) * 100)}%`,
                backgroundImage: 'linear-gradient(90deg,#2b6b3a,#79ff8f,#58d6e0)',
              }}
            />
            <div className="flex items-center justify-between px-4 py-2 text-[10px] uppercase tracking-[0.2em] text-dim">
              <span>
                lines {rendered.length}/{total}
              </span>
              <div className="flex items-center gap-4">
                <span className={done ? 'text-pho' : ''}>{done ? 'complete' : playing ? 'running' : 'paused'}</span>
                <CopyButton text={transcript} label="transcript" className="!py-1 !px-2" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

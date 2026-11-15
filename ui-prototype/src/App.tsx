import { useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import "./App.css";
import { DeviceCard, type DeviceCardData } from "@/components/devices/DeviceCard";

/**
 * DeviceCard prototype lab.
 *
 * The layout is intentionally generous so the card can move freely
 * — the coding AI reads the card, not the page chrome, when porting to Flutter.
 */

const BASE: DeviceCardData = {
  deviceType: "windows-desktop",
  name: "Likianta's office rig",
  address: "47.102.108.149",
  url: "http://47.102.108.149:2160",
  hostKind: "remote",
  host: "47.102.108.149",
  port: 2160,
  pairId: "24a3f252df3f151002dd7261036bbbcb54c3efbf214ad04d",
  rootPath: "/Users/Likianta/Desktop/work/likianta-projects",
  pairs: [
    {
      label: "photolens",
      localPath: "/Users/Likianta/Desktop/work/likianta-projects/photolens",
    },
    {
      label: "pictures-inbox-test",
      localPath:
        "/Users/Likianta/Desktop/temp/2026-11/pictures-inbox-test",
    },
  ],
};

function App() {
  const [data, setData] = useState<DeviceCardData>(BASE);
  const [cardKey, setCardKey] = useState(0);
  const [theme, setTheme] = useState<"light" | "dark">("light");

  // Arc foundation reads `data-theme` and `data-accent` from <html>.
  const htmlEl =
    typeof document !== "undefined" ? document.documentElement : null;
  if (htmlEl) {
    htmlEl.setAttribute("data-theme", theme);
    htmlEl.setAttribute("data-accent", "blue");
  }

  return (
    <div className="relative min-h-screen overflow-hidden bg-[var(--background)] text-[var(--foreground)]">
      {/* Ambient gradient wash — quiet neo-skeuo backdrop */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 -z-10 opacity-60"
        style={{
          backgroundImage:
            "radial-gradient(circle at 20% 10%, color-mix(in oklab, var(--tone-sky) 22%, transparent), transparent 60%), radial-gradient(circle at 85% 90%, color-mix(in oklab, var(--tone-violet) 14%, transparent), transparent 55%)",
        }}
      />

      {/* Top bar — same arc-demo header, compact */}
      <header className="sticky top-0 z-40 flex items-center justify-between border-b border-[var(--border-subtle)] bg-[color-mix(in_oklab,var(--surface)_78%,transparent)] px-10 py-4 backdrop-blur-xl">
        <div className="flex items-center gap-3">
          <div className="flex h-8 w-8 items-center justify-center rounded-[var(--radius-control)] bg-[var(--accent)] text-[var(--accent-foreground)] shadow-[var(--shadow-resting)]">
            <span className="text-sm font-semibold">FP</span>
          </div>
          <span className="text-sm font-medium tracking-[-0.005em] text-[var(--foreground)]">
            DeviceCard · UI lab
          </span>
          <span className="ml-2 rounded-[var(--radius-pill)] border border-[var(--border-subtle)] px-2 py-0.5 text-[11px] font-medium uppercase tracking-[0.08em] text-[var(--text-muted)]">
            prototype
          </span>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() =>
              setTheme((t) => (t === "light" ? "dark" : "light"))
            }
            className="flex h-8 items-center gap-1.5 rounded-[var(--radius-control)] border border-[var(--border-subtle)] bg-[var(--surface-muted)] px-3 text-[12px] font-medium text-[var(--text-secondary)] transition-colors hover:text-[var(--foreground)] active:scale-95"
          >
            {theme === "light" ? "☾ Dark" : "☀ Light"}
          </button>
          <button
            onClick={() => {
              setCardKey((k) => k + 1);
              setData(BASE);
            }}
            className="flex h-8 items-center gap-1.5 rounded-[var(--radius-control)] border border-[var(--border-subtle)] bg-[var(--surface-muted)] px-3 text-[12px] font-medium text-[var(--text-secondary)] transition-colors hover:text-[var(--foreground)] active:scale-95"
          >
            ↻ Reset
          </button>
        </div>
      </header>

      <main className="mx-auto flex max-w-6xl flex-col gap-10 px-10 py-14">
        {/* Intro */}
        <div className="flex flex-col gap-2">
          <h1 className="text-[28px] font-semibold tracking-[-0.02em] text-[var(--foreground)]">
            Remote device card
          </h1>
          <p className="max-w-xl text-[var(--text-sm)] leading-[1.6] text-[var(--text-muted)]">
            A single desktop card that represents one peer machine in the sync
            network. 340 × wraps, Neo-skeuo surfaces, continuous radii,
            spring-driven three-state mouse feedback. Every element here is
            either Arc motion-tokens or pure Tailwind tokens — no random
            inline styles.
          </p>
        </div>

        {/* Row: DeviceCard + debug panel */}
        <div className="grid grid-cols-1 gap-8 md:grid-cols-[auto_1fr] md:items-start">
          <AnimatePresence mode="wait">
            <DeviceCard
              key={cardKey}
              data={data}
              onChange={setData}
            />
          </AnimatePresence>

          {/* Right-side debug panel: live state of the card */}
          <motion.aside
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.12 }}
            className="rounded-[var(--radius-surface)] border border-[var(--border-subtle)] bg-[var(--surface)] p-6 shadow-[var(--shadow-raised)]"
          >
            <div className="mb-4 text-[var(--text-sm)] font-semibold text-[var(--foreground)]">
              Live card state
            </div>
            <pre className="max-h-[420px] overflow-auto rounded-[var(--radius-panel)] bg-[var(--surface-muted)] p-4 text-[12px] leading-[1.6] text-[var(--text-secondary)]">
{JSON.stringify(data, null, 2)}
            </pre>
          </motion.aside>
        </div>

        <footer className="pt-4 text-center text-[11px] uppercase tracking-[0.1em] text-[var(--text-muted)]">
          ui-prototype · vite + react 19 + tailwind v4 + arc library · port 5173
        </footer>
      </main>
    </div>
  );
}

export default App;

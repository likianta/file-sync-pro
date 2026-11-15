import { useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { Folder, Pencil, Trash2, Plus, RefreshCw, Info } from "lucide-react";
import type { DeviceType } from "./DeviceIcon";
import { DeviceIcon } from "./DeviceIcon";

/* -------------------------------------------------------------------------- */
/*  Types                                                                     */
/* -------------------------------------------------------------------------- */

export interface Pair {
  /** Display name of the remote mount (e.g. "photolens"). */
  label: string;
  /** Absolute path on THIS computer where the sync lives. */
  localPath: string;
}

export interface DeviceCardData {
  /** What the other end claims to be. */
  deviceType: DeviceType;
  /** Editable alias, falls back to `address`. */
  name: string;
  /** Hostname or IP. */
  address: string;
  /** Full transport URL for display. */
  url: string;
  /** Local vs Remote host type. */
  hostKind: "local" | "remote";
  host: string;
  port: number;
  /** Current local pair ID (hex) shown in the info popup. */
  pairId: string;
  /** Directory on THIS machine that mirrors the pair. */
  rootPath: string;
  pairs: Pair[];
}

const DEFAULT: DeviceCardData = {
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
    { label: "photolens", localPath: "/Users/Likianta/Desktop/work/likianta-projects/photolens" },
    { label: "pictures-inbox-test", localPath: "/Users/Likianta/Desktop/temp/2026-11/pictures-inbox-test" },
  ],
};

/* -------------------------------------------------------------------------- */
/*  Chips (continuous radius, three-state feedback)                           */
/* -------------------------------------------------------------------------- */

interface ChipProps<T extends string> {
  options: readonly { value: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
}

function ChipGroup<T extends string>({ options, value, onChange }: ChipProps<T>) {
  return (
    <div
      className="flex items-center gap-1 rounded-[var(--radius-panel)] border border-[var(--border-subtle)] bg-[var(--surface-muted)] p-1"
      role="radiogroup"
    >
      {options.map((o) => {
        const active = o.value === value;
        return (
          <button
            key={o.value}
            role="radio"
            aria-checked={active}
            onClick={() => onChange(o.value)}
            className={
              "relative z-10 flex items-center gap-1.5 rounded-[var(--radius-pill)] px-3 py-1.5 text-[var(--text-sm)] font-medium tracking-[-0.005em] transition-colors duration-[var(--duration-fast)] ease-[var(--ease-standard)] " +
              (active
                ? "text-[var(--accent-foreground)]"
                : "text-[var(--text-secondary)] hover:text-[var(--foreground)]")
            }
          >
            {o.label}
            {active && (
              <motion.span
                layoutId="chip-indicator"
                className="absolute inset-0 -z-10 rounded-[var(--radius-pill)] bg-[var(--accent)] shadow-[var(--shadow-resting)]"
                transition={{ type: "spring", stiffness: 420, damping: 30, mass: 0.6 }}
              />
            )}
          </button>
        );
      })}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Icon button — leave / enter / press three-state feedback                  */
/* -------------------------------------------------------------------------- */

interface IconBtnProps extends Omit<React.ComponentProps<typeof motion.button>, "children"> {
  children: React.ReactNode;
  variant?: "ghost" | "danger";
}

function IconBtn({ children, variant = "ghost", className = "", ...p }: IconBtnProps) {
  const danger = variant === "danger";
  return (
    <motion.button
      whileHover={{ scale: 1.08, y: -1 }}
      whileTap={{ scale: 0.94, y: 0, boxShadow: "inset 0 1px 2px rgba(0,0,0,.12)" }}
      transition={{ type: "spring", stiffness: 520, damping: 26, mass: 0.4 }}
      className={
        "flex h-8 w-8 items-center justify-center rounded-[var(--radius-control)] border border-transparent text-[var(--text-secondary)] transition-colors duration-[var(--duration-fast)] " +
        (danger
          ? "hover:border-[var(--tone-rose)] hover:bg-[color-mix(in_oklab,var(--tone-rose)_14%,transparent)] hover:text-[var(--tone-rose)]"
          : "hover:border-[var(--border-subtle)] hover:bg-[var(--surface-muted)] hover:text-[var(--foreground)]") +
        " " + className
      }
      {...p}
    >
      {children}
    </motion.button>
  );
}

/* -------------------------------------------------------------------------- */
/*  Section label + input                                                     */
/* -------------------------------------------------------------------------- */

function Label({ children }: { children: React.ReactNode }) {
  return (
    <div className="text-[var(--text-xs)] font-semibold uppercase tracking-[0.08em] text-[var(--text-muted)]">
      {children}
    </div>
  );
}

interface FieldProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
}

function Field({ label, className = "", ...p }: FieldProps) {
  return (
    <label className="flex flex-col gap-1.5">
      {label && <Label>{label}</Label>}
      <input
        {...p}
        className={
          "h-[var(--control-height-md)] w-full rounded-[var(--radius-control)] border border-[var(--border)] bg-[var(--surface)] px-3 text-[var(--text-field)] text-[var(--foreground)] shadow-[inset_0_0_0_1px_transparent,_0_1px_0_rgba(255,255,255,0.04)] transition-all duration-[var(--duration-fast)] " +
          "placeholder:text-[var(--text-muted)] " +
          "hover:border-[var(--border-strong)] " +
          "focus:border-[var(--accent)] focus:outline-none focus:ring-2 focus:ring-[var(--accent-subtle)] " +
          "active:shadow-[inset_0_2px_4px_rgba(0,0,0,0.06)] " +
          "disabled:cursor-not-allowed disabled:bg-[var(--surface-muted)] disabled:text-[var(--text-muted)] " +
          className
        }
      />
    </label>
  );
}

/* -------------------------------------------------------------------------- */
/*  Pairs list row                                                            */
/* -------------------------------------------------------------------------- */

function PairRow({ pair, index }: { pair: Pair; index: number }) {
  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -6, scale: 0.98 }}
      transition={{
        type: "spring",
        stiffness: 400,
        damping: 28,
        mass: 0.5,
        delay: index * 0.03,
      }}
      className="group flex items-center gap-3 rounded-[var(--radius-panel)] border border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2.5 transition-all duration-[var(--duration-fast)] hover:border-[var(--border)] hover:bg-[var(--surface-raised)] hover:shadow-[var(--shadow-resting)]"
    >
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[var(--radius-control)] bg-[var(--accent-subtle)] text-[var(--accent)]">
        <Folder size={16} strokeWidth={2} />
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-[var(--text-sm)] font-medium text-[var(--foreground)]">
          {pair.label}
        </div>
        <div className="truncate text-[var(--text-xs)] text-[var(--text-muted)]">
          {pair.localPath}
        </div>
      </div>
      <div className="flex items-center gap-1 opacity-0 transition-opacity duration-[var(--duration-fast)] group-hover:opacity-100">
        <IconBtn aria-label="Edit pair">
          <Pencil size={14} strokeWidth={2} />
        </IconBtn>
        <IconBtn variant="danger" aria-label="Delete pair">
          <Trash2 size={14} strokeWidth={2} />
        </IconBtn>
      </div>
    </motion.div>
  );
}

/* -------------------------------------------------------------------------- */
/*  DeviceCard                                                                */
/* -------------------------------------------------------------------------- */

const DEVICE_CHIPS: { value: DeviceType; label: string }[] = [
  { value: "windows-desktop", label: "Windows" },
  { value: "macbook", label: "macOS" },
  { value: "linux-desktop", label: "Linux" },
  { value: "android-phone", label: "Android" },
];

const HOST_CHIPS: { value: "local" | "remote"; label: string }[] = [
  { value: "local", label: "Local" },
  { value: "remote", label: "Remote" },
];

export function DeviceCard({
  data = DEFAULT,
  onChange,
}: {
  data?: DeviceCardData;
  onChange?: (next: DeviceCardData) => void;
}) {
  const set = <K extends keyof DeviceCardData>(k: K, v: DeviceCardData[K]) =>
    onChange?.({ ...data, [k]: v });

  return (
    <motion.article
      layout
      initial={{ opacity: 0, y: 12, scale: 0.98 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ type: "spring", stiffness: 320, damping: 28, mass: 0.8 }}
      className="w-[340px] rounded-[var(--radius-surface)] border border-[var(--border-subtle)] bg-[var(--surface)] p-5 shadow-[var(--shadow-raised)]"
    >
      {/* ---- Top: device icon + name + address + delete -------- */}
      <div className="flex items-start gap-4">
        <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-[var(--radius-panel)] border border-[var(--border-subtle)] bg-[var(--surface-muted)] shadow-[var(--shadow-resting)]">
          <AnimatePresence mode="wait">
            <DeviceIcon key={data.deviceType} type={data.deviceType} size={64} />
          </AnimatePresence>
        </div>

        <div className="min-w-0 flex-1 pt-1">
          <input
            value={data.name}
            onChange={(e) => set("name", e.target.value)}
            className="w-full truncate bg-transparent text-[var(--text-lg)] font-semibold tracking-[-0.015em] text-[var(--foreground)] outline-none focus:text-[var(--accent)]"
          />
          <div className="mt-0.5 flex items-center gap-2 text-[var(--text-xs)] text-[var(--text-muted)]">
            <span className="truncate">{data.address}</span>
            <span className="opacity-40">·</span>
            <a
              href="#"
              onClick={(e) => e.preventDefault()}
              className="truncate hover:text-[var(--accent)]"
            >
              {data.url}
            </a>
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-1">
          <InfoPopup data={data} />
          <IconBtn aria-label="Delete device" variant="danger">
            <Trash2 size={16} strokeWidth={2} />
          </IconBtn>
        </div>
      </div>

      <div className="my-5 h-px bg-[var(--border-subtle)]" />

      {/* ---- Chips rows ---------------------------------------- */}
      <div className="space-y-4">
        <div className="flex items-center justify-between gap-3">
          <Label>Device type</Label>
          <ChipGroup
            options={DEVICE_CHIPS}
            value={data.deviceType}
            onChange={(v) => set("deviceType", v)}
          />
        </div>
        <div className="flex items-center justify-between gap-3">
          <Label>Host type</Label>
          <ChipGroup
            options={HOST_CHIPS}
            value={data.hostKind}
            onChange={(v) => set("hostKind", v)}
          />
        </div>
      </div>

      <div className="my-5 h-px bg-[var(--border-subtle)]" />

      {/* ---- Host + Port --------------------------------------- */}
      <div className="grid grid-cols-3 gap-3">
        <div className="col-span-2">
          <Field
            label="Host"
            value={data.host}
            onChange={(e) => set("host", e.target.value)}
          />
        </div>
        <Field
          label="Port"
          inputMode="numeric"
          value={String(data.port)}
          onChange={(e) => set("port", Number(e.target.value) || 0)}
        />
      </div>

      <div className="my-5 h-px bg-[var(--border-subtle)]" />

      {/* ---- Pairs --------------------------------------------- */}
      <div>
        <div className="mb-3 flex items-center justify-between">
          <Label>
            Pairs <span className="ml-1 font-medium text-[var(--text-muted)]">({data.pairs.length})</span>
          </Label>
          <div className="flex items-center gap-1">
            <IconBtn aria-label="Refresh pairs">
              <RefreshCw size={15} strokeWidth={2} />
            </IconBtn>
            <IconBtn aria-label="Add pair">
              <Plus size={16} strokeWidth={2.4} />
            </IconBtn>
          </div>
        </div>

        <div className="space-y-2">
          <AnimatePresence initial={false}>
            {data.pairs.map((p, i) => (
              <PairRow key={p.label} pair={p} index={i} />
            ))}
          </AnimatePresence>
        </div>
      </div>
    </motion.article>
  );
}

export default DeviceCard;

/* -------------------------------------------------------------------------- */
/*  Info popup — click the info icon, spring-in a floating panel              */
/* -------------------------------------------------------------------------- */

function InfoPopup({ data }: { data: DeviceCardData }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative">
      <IconBtn aria-label="Connection info" onClick={() => setOpen((o) => !o)}>
        <Info size={16} strokeWidth={2} />
      </IconBtn>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -6, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -4, scale: 0.98 }}
            transition={{ type: "spring", stiffness: 380, damping: 26 }}
            className="absolute right-0 top-10 z-20 w-[360px] rounded-[var(--radius-panel)] border border-[var(--border-subtle)] bg-[var(--surface-raised)] p-4 shadow-[var(--shadow-floating)] backdrop-blur"
          >
            <div className="mb-3 text-[var(--text-sm)] font-semibold text-[var(--foreground)]">
              Connection details
            </div>
            <div className="space-y-3">
              <Field label="Pair ID (shared)" value={data.pairId} readOnly />
              <Field label="Root path on remote" value={data.rootPath} readOnly />
              <label className="flex flex-col gap-1.5">
                <Label>Local sync folder</Label>
                <div className="flex gap-2">
                  <input
                    defaultValue={data.rootPath}
                    className="h-[var(--control-height-md)] flex-1 rounded-[var(--radius-control)] border border-[var(--border)] bg-[var(--surface)] px-3 text-[var(--text-field)] text-[var(--foreground)] outline-none focus:border-[var(--accent)]"
                  />
                  <button
                    className="flex h-[var(--control-height-md)] items-center rounded-[var(--radius-control)] border border-[var(--border)] bg-[var(--surface-muted)] px-3 text-[var(--text-sm)] font-medium text-[var(--foreground)] transition hover:border-[var(--accent)] hover:text-[var(--accent)] active:scale-95"
                    onClick={() => setOpen(false)}
                  >
                    Browse
                  </button>
                </div>
              </label>
            </div>
            <div className="mt-4 flex justify-end">
              <button
                className="rounded-[var(--radius-pill)] bg-[var(--accent)] px-4 py-1.5 text-[var(--text-sm)] font-medium text-[var(--accent-foreground)] transition hover:opacity-90 active:scale-95"
                onClick={() => setOpen(false)}
              >
                Done
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

import { motion } from "motion/react";
import type { ComponentProps, SVGProps } from "react";

/** 7 device archetypes as line-art SVGs, each framed to 64×64 and styled
 *  with a subtle drop-shadow body so they feel like 3D artifacts on the card.
 *  Switching device chips fades one SVG out and springs the next in. */
export type DeviceType =
  | "macbook"
  | "windows-laptop"
  | "windows-desktop"
  | "linux-desktop"
  | "iphone"
  | "ipad"
  | "android-phone";

interface Props extends ComponentProps<typeof motion.svg> {
  type: DeviceType;
  size?: number;
}

const wrapProps = {
  xmlns: "http://www.w3.org/2000/svg",
  viewBox: "0 0 64 64",
  fill: "none",
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

function Macbook(p: SVGProps<SVGSVGElement>) {
  return (
    <svg {...wrapProps} {...p}>
      {/* Base / shadow deck */}
      <rect x="6" y="46" width="52" height="4" rx="1.2" fill="var(--border-subtle)" />
      {/* Screen body */}
      <rect x="10" y="12" width="44" height="34" rx="3" stroke="var(--border-strong)" strokeWidth="1.4" fill="var(--surface)" />
      {/* Screen fill */}
      <rect x="12" y="14" width="40" height="28" rx="1.5" fill="var(--accent-subtle)" />
      {/* Keyboard deck */}
      <rect x="4" y="48" width="56" height="5" rx="1.5" stroke="var(--border-strong)" strokeWidth="1.4" fill="var(--surface-muted)" />
      {/* Notch */}
      <rect x="28" y="10.5" width="8" height="1.5" rx="0.6" fill="var(--border-strong)" />
    </svg>
  );
}

function WindowsLaptop(p: SVGProps<SVGSVGElement>) {
  return (
    <svg {...wrapProps} {...p}>
      <rect x="6" y="48" width="52" height="3" rx="1" fill="var(--border-subtle)" />
      <rect x="9" y="12" width="46" height="36" rx="2" stroke="var(--border-strong)" strokeWidth="1.4" fill="var(--surface)" />
      <rect x="11" y="14" width="42" height="30" rx="1" fill="var(--tone-sky)" opacity="0.18" />
      {/* Windows "grid" mark on bottom-right of screen */}
      <rect x="36" y="34" width="3" height="3" fill="var(--tone-sky)" />
      <rect x="40" y="34" width="3" height="3" fill="var(--tone-sky)" />
      <rect x="36" y="38" width="3" height="3" fill="var(--tone-sky)" />
      <rect x="40" y="38" width="3" height="3" fill="var(--tone-sky)" />
      {/* Kickstand hinge */}
      <rect x="3" y="49" width="58" height="4" rx="1.5" stroke="var(--border-strong)" strokeWidth="1.4" fill="var(--surface-muted)" />
    </svg>
  );
}

function WindowsDesktop(p: SVGProps<SVGSVGElement>) {
  return (
    <svg {...wrapProps} {...p}>
      {/* Screen */}
      <rect x="8" y="8" width="48" height="34" rx="2" stroke="var(--border-strong)" strokeWidth="1.4" fill="var(--surface)" />
      <rect x="10" y="10" width="44" height="28" rx="1" fill="var(--tone-sky)" opacity="0.18" />
      {/* Stand neck */}
      <rect x="29" y="42" width="6" height="10" rx="1" fill="var(--border-strong)" />
      {/* Stand base */}
      <ellipse cx="32" cy="55" rx="16" ry="2.5" stroke="var(--border-strong)" strokeWidth="1.4" fill="var(--surface-muted)" />
      <rect x="20" y="53" width="24" height="3" rx="1.5" fill="var(--surface-muted)" />
      {/* Windows grid */}
      <rect x="16" y="16" width="4" height="4" fill="var(--tone-sky)" />
      <rect x="21" y="16" width="4" height="4" fill="var(--tone-sky)" />
      <rect x="16" y="22" width="4" height="4" fill="var(--tone-sky)" />
      <rect x="21" y="22" width="4" height="4" fill="var(--tone-sky)" />
    </svg>
  );
}

function LinuxDesktop(p: SVGProps<SVGSVGElement>) {
  return (
    <svg {...wrapProps} {...p}>
      <rect x="8" y="8" width="48" height="34" rx="2" stroke="var(--border-strong)" strokeWidth="1.4" fill="var(--surface)" />
      <rect x="10" y="10" width="44" height="28" rx="1" fill="var(--tone-teal)" opacity="0.18" />
      {/* Penguin "Tux" silhouette hint */}
      <circle cx="32" cy="22" r="5" stroke="var(--tone-teal)" strokeWidth="1.4" fill="var(--surface)" />
      <path d="M27 27 Q32 36 37 27 L35 24 L29 24 Z" fill="var(--tone-teal)" opacity="0.5" />
      <rect x="29" y="42" width="6" height="10" rx="1" fill="var(--border-strong)" />
      <ellipse cx="32" cy="55" rx="16" ry="2.5" stroke="var(--border-strong)" strokeWidth="1.4" fill="var(--surface-muted)" />
      <rect x="20" y="53" width="24" height="3" rx="1.5" fill="var(--surface-muted)" />
    </svg>
  );
}

function IPhone(p: SVGProps<SVGSVGElement>) {
  return (
    <svg {...wrapProps} {...p}>
      <rect x="18" y="6" width="28" height="52" rx="7" stroke="var(--border-strong)" strokeWidth="1.6" fill="var(--surface)" />
      <rect x="20" y="10" width="24" height="44" rx="3" fill="var(--tone-violet)" opacity="0.15" />
      {/* Dynamic island */}
      <rect x="26" y="13" width="12" height="4" rx="2" fill="var(--border-strong)" />
      {/* Home indicator */}
      <rect x="26" y="55" width="12" height="1.2" rx="0.6" fill="var(--border-strong)" opacity="0.6" />
    </svg>
  );
}

function IPad(p: SVGProps<SVGSVGElement>) {
  return (
    <svg {...wrapProps} {...p}>
      <rect x="6" y="10" width="52" height="44" rx="5" stroke="var(--border-strong)" strokeWidth="1.6" fill="var(--surface)" />
      <rect x="10" y="14" width="44" height="36" rx="2" fill="var(--tone-violet)" opacity="0.15" />
      {/* Camera dot */}
      <circle cx="32" cy="8" r="1.2" fill="var(--border-strong)" />
      {/* Home indicator */}
      <rect x="27" y="51" width="10" height="1.2" rx="0.6" fill="var(--border-strong)" opacity="0.5" />
    </svg>
  );
}

function AndroidPhone(p: SVGProps<SVGSVGElement>) {
  return (
    <svg {...wrapProps} {...p}>
      <rect x="18" y="6" width="28" height="52" rx="5" stroke="var(--border-strong)" strokeWidth="1.6" fill="var(--surface)" />
      <rect x="20" y="12" width="24" height="40" rx="2" fill="var(--tone-green)" opacity="0.18" />
      {/* Camera pill (centered hole-punch) */}
      <circle cx="32" cy="10" r="1.6" fill="var(--border-strong)" />
      {/* Android robot head hint */}
      <path d="M26 30 Q32 25 38 30 L36 36 L28 36 Z" fill="var(--tone-green)" opacity="0.6" />
      <circle cx="29" cy="31" r="0.8" fill="var(--surface)" />
      <circle cx="35" cy="31" r="0.8" fill="var(--surface)" />
      {/* Nav bar */}
      <rect x="23" y="51" width="18" height="1.2" rx="0.6" fill="var(--border-strong)" opacity="0.5" />
    </svg>
  );
}

const MAP: Record<DeviceType, (p: SVGProps<SVGSVGElement>) => React.ReactNode> = {
  macbook: Macbook,
  "windows-laptop": WindowsLaptop,
  "windows-desktop": WindowsDesktop,
  "linux-desktop": LinuxDesktop,
  iphone: IPhone,
  ipad: IPad,
  "android-phone": AndroidPhone,
};

export function DeviceIcon({ type, size = 72, ...props }: Props) {
  const Svg = MAP[type];
  return (
    <motion.svg
      width={size}
      height={size}
      initial={{ opacity: 0, scale: 0.92, y: 4 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.96 }}
      transition={{ type: "spring", stiffness: 260, damping: 22 }}
      {...wrapProps}
      {...props}
    >
      <Svg />
    </motion.svg>
  );
}

export default DeviceIcon;

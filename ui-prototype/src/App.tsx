import { useState } from "react";
import "./App.css";

// --- Arc components ----------------------------------------------------------------------------
import { Button } from "@/components/arc/button/button";
import {
  Dialog,
  DialogTrigger,
  DialogContent,
  DialogClose,
  DialogTitle,
  DialogDescription,
} from "@/components/arc/dialog/dialog";
import {
  Tabs,
  TabsList,
  TabsTrigger,
  TabsContent,
} from "@/components/arc/tabs/tabs";
import { Switch } from "@/components/arc/switch/switch";

function Section({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="rounded-3xl border border-border bg-surface-raised/60 p-8 shadow-[0_1px_0_rgba(255,255,255,0.06)_inset] backdrop-blur">
      <div className="mb-6">
        <h2 className="text-lg font-medium tracking-tight text-foreground">
          {title}
        </h2>
        {description && (
          <p className="mt-1 text-sm text-muted-foreground">{description}</p>
        )}
      </div>
      {children}
    </section>
  );
}

function App() {
  const [syncEnabled, setSyncEnabled] = useState(true);

  return (
    <div className="min-h-screen bg-background text-foreground">
      {/* Top bar */}
      <header className="sticky top-0 z-50 flex items-center justify-between border-b border-border bg-background/80 px-10 py-4 backdrop-blur">
        <div className="flex items-center gap-3">
          <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-accent text-sm font-semibold text-accent-foreground">
            FP
          </div>
          <span className="text-sm font-medium tracking-tight">
            File Sync Pro · UI Lab
          </span>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="ghost" size="sm">
            Share
          </Button>
          <Button size="sm">New Pair</Button>
        </div>
      </header>

      <main className="mx-auto flex max-w-6xl flex-col gap-8 px-10 py-12">
        {/* Hero */}
        <div className="flex flex-col gap-2">
          <h1 className="text-3xl font-semibold tracking-tight">
            Arc × Tailwind prototype lab
          </h1>
          <p className="max-w-xl text-muted-foreground">
            Each card below is a standalone Arc component wired up with dummy
            data. The coding AI reads this visual language and re-implements
            it in Flutter.
          </p>
        </div>

        {/* Buttons */}
        <Section
          title="Button"
          description="Three states. Default, ghost, and destructive. Hover/press/leave all produce spring feedback."
        >
          <div className="flex flex-wrap items-center gap-3">
            <Button>Sync now</Button>
            <Button variant="ghost">Cancel</Button>
            <Button variant="destructive">Delete pair</Button>
            <Button disabled>Disabled</Button>
          </div>
        </Section>

        {/* Switch */}
        <Section title="Switch" description="Tactile toggle with spring thumb.">
          <div className="flex items-center gap-6">
            <label className="flex items-center gap-3 text-sm">
              <Switch
                checked={syncEnabled}
                onCheckedChange={setSyncEnabled}
              />
              Real-time sync
            </label>
            <span className="text-xs text-muted-foreground">
              {syncEnabled ? "on" : "off"}
            </span>
          </div>
        </Section>

        {/* Tabs */}
        <Section
          title="Tabs"
          description="Sliding indicator, smooth height morph when content switches."
        >
          <Tabs defaultValue="sync">
            <TabsList>
              <TabsTrigger value="sync">Sync</TabsTrigger>
              <TabsTrigger value="server">Server</TabsTrigger>
              <TabsTrigger value="settings">Settings</TabsTrigger>
            </TabsList>
            <TabsContent value="sync">
              <div className="py-6 text-sm text-muted-foreground">
                Last synced 4 min ago · 128 files · 3 conflicts need review.
              </div>
            </TabsContent>
            <TabsContent value="server">
              <div className="py-6 text-sm text-muted-foreground">
                Server bound to 0.0.0.0:2160 · 3 mounts active · 2 devices
                connected.
              </div>
            </TabsContent>
            <TabsContent value="settings">
              <div className="py-6 text-sm text-muted-foreground">
                Theme: auto · Accent: blue · Hash cache: enabled · Retries: 3.
              </div>
            </TabsContent>
          </Tabs>
        </Section>

        {/* Dialog */}
        <Section
          title="Dialog"
          description="Portal, backdrop fade + spring scale on enter. Shortened transition on close."
        >
          <Dialog>
            <DialogTrigger asChild>
              <Button variant="outline">Resolve conflicts…</Button>
            </DialogTrigger>
            <DialogContent>
              <DialogTitle>Keep local or remote?</DialogTitle>
              <DialogDescription>
                3 files differ between your machine and the server. Pick a
                side for each, or bulk-keep one side.
              </DialogDescription>
              <div className="mt-6 flex justify-end gap-2">
                <DialogClose asChild>
                  <Button variant="ghost">Cancel</Button>
                </DialogClose>
                <Button variant="destructive">Keep local</Button>
                <Button>Keep remote</Button>
              </div>
            </DialogContent>
          </Dialog>
        </Section>

        {/* Card grid — custom Tailwind surfaces */}
        <Section
          title="Surface layers"
          description="Cards with layered shadow tokens and three elevation levels."
        >
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            {[
              { label: "Idle", surface: "bg-surface border-border" },
              {
                label: "Raised",
                surface:
                  "bg-surface-raised border-border shadow-[0_1px_0_rgba(255,255,255,0.06)_inset,0_8px_24px_-12px_rgba(0,0,0,0.5)]",
              },
              {
                label: "Pressed",
                surface:
                  "bg-surface-muted border-border shadow-[0_1px_2px_rgba(0,0,0,0.4)_inset]",
              },
            ].map((card) => (
              <div
                key={card.label}
                className={`rounded-2xl border p-6 transition-all duration-200 ${card.surface}`}
              >
                <div className="text-sm font-medium">{card.label}</div>
                <div className="mt-1 text-xs text-muted-foreground">
                  Surface token demo
                </div>
              </div>
            ))}
          </div>
        </Section>

        <footer className="pt-4 text-center text-xs text-muted-foreground">
          ui-prototype · vite + react 19 + tailwind v4 + arc · source lives in{" "}
          <code>src/</code>, dev server on port 5173
        </footer>
      </main>
    </div>
  );
}

export default App;

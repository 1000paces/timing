# Ops Console v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A browser console where a chief signs in, picks an event and start group, presses GO, sets the lap count, watches standings refresh, and clears the review queue.

**Architecture:** One Vite + React + TypeScript app in `frontend/`, built into `public/console/` and served by Rails as static files at `/console/`. It talks to the existing API: `POST/GET/DELETE /session`, `POST /graphql` (Apollo Client), and `/cable` (`EventChannel`) for "changed" pushes, plus a 5 s poll as a safety net. No API changes. A Playwright test drives Rails in the test environment (its own SQLite file) with the race simulator.

**Tech Stack:** Node 24, npm, Vite 8, React 19, TypeScript, Apollo Client 4 (+ rxjs), graphql, @rails/actioncable, Vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-10-02-ops-console-v1-design.md` (parent: `docs/superpowers/specs/2026-10-01-hub-mvp-design.md` §6)

## Global Constraints

- v1 scope only (spec §3). Nothing from spec §4 "Not in v1". No Rails API changes.
- Laptop/desktop layout; no responsive or touch work.
- Console URL `/console/`; Vite `base: "/console/"`; build output `public/console/` (git-ignored).
- Three views via URL hash: `#/`, `#/events/:id`, `#/events/:id/groups/:groupId`. No router library.
- Action controls (GO, lap count, Accept, Dismiss) only for roles `chief` and `admin`.
- Live refresh: `EventChannel` "changed" → refetch after ~300 ms debounce; plus `pollInterval` 5000 ms.
- Dev: Vite on 5173 proxies `/session`, `/graphql`, `/cable` to Rails on 3000; Rails needs `TIMING_ALLOWED_ORIGINS=http://localhost:5173`.
- E2E: Rails `RAILS_ENV=test` with `TIMING_SQLITE_PATH=storage/e2e.sqlite3` on `127.0.0.1:3200`.
- Ruby side unchanged except: `config/database.yml` test path override, `.gitignore`, `lib/tasks/console.rake`, `bin/hub`, `bin/console-dev`, `bin/e2e-server`, runbook, CI.

## Review Focus

1. **Double-clicking GO** must record one start, not two (a second GO moves the gun). Test in Task 3 (`dblclick`, then count rulings).
2. **Session ends mid-race** (server restart, sign-out elsewhere): the console returns to sign-in instead of a broken page. Test in Task 1 (`isSignedOutError`) and wiring in Tasks 2–3.
3. **A timer signs in**: they see standings and the queue but no action buttons. Test in Task 2 (e2e).
4. **Accepting a suggestion someone else already handled**: the error shows inline and the list refreshes. Wired in Task 3.
5. **A failed refresh** (hub busy, network blip): the error shows above the panel and the last data stays visible. Wired in Task 3.

---

## File Structure

```
frontend/
  package.json, package-lock.json, tsconfig.json, vite.config.ts, vitest.config.ts, playwright.config.ts, index.html
  src/main.tsx            entry: Apollo provider + App
  src/styles.css
  src/api.ts              Apollo client
  src/session.ts          /session calls + Official type
  src/route.ts            hash routes (parseRoute, eventHref, useRoute)
  src/format.ts           formatElapsed, formatGap, formatClock
  src/roles.ts            canAct, isSignedOutError
  src/queries.ts          GraphQL documents + result types
  src/useEventChanges.ts  EventChannel subscription
  src/App.tsx             shell: loading / sign-in / views
  src/views/SignIn.tsx, Events.tsx, RaceScreen.tsx, GroupControls.tsx, Standings.tsx, ReviewQueue.tsx
  src/*.test.ts           Vitest
  e2e/seed.rb             seeds the e2e database
  e2e/simulate.rb         writes a simulated race after GO
  e2e/sign-in.spec.ts, e2e/race.spec.ts
bin/e2e-server, bin/console-dev
bin/hub                  (modify) build console if missing
lib/tasks/console.rake
config/database.yml      (modify) TIMING_SQLITE_PATH for test
.gitignore, .github/workflows/ci.yml, docs/hub-runbook.md (modify)
```

---

### Task 1: Frontend scaffold, helpers, unit tests, CI job

**Files:**
- Create: `frontend/package.json`, `frontend/tsconfig.json`, `frontend/vite.config.ts`, `frontend/vitest.config.ts`, `frontend/index.html`, `frontend/src/main.tsx`, `frontend/src/App.tsx` (placeholder), `frontend/src/styles.css`, `frontend/src/route.ts`, `frontend/src/format.ts`, `frontend/src/roles.ts`, `frontend/src/route.test.ts`, `frontend/src/format.test.ts`, `frontend/src/roles.test.ts`, `lib/tasks/console.rake`
- Modify: `.gitignore`, `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `parseRoute(hash) -> Route`, `eventHref(eventId, groupId?)`, `useRoute()`; `formatElapsed(ms)`, `formatGap(lapsDown, ms)`, `formatClock(ms)`; `canAct(role)`, `isSignedOutError(error)`; rake `console:build`; npm scripts `dev`, `build`, `typecheck`, `test`.

- [ ] **Step 1: Package and config files**

`frontend/package.json`:
```json
{
  "name": "timing-console",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "e2e": "vite build && playwright test"
  },
  "dependencies": {
    "@apollo/client": "^4.3.1",
    "@rails/actioncable": "^8.1.400",
    "graphql": "^16.11.0",
    "react": "^19.3.0",
    "react-dom": "^19.3.0",
    "rxjs": "^7.8.2"
  },
  "devDependencies": {
    "@playwright/test": "^1.63.0",
    "@types/node": "^24.0.0",
    "@types/rails__actioncable": "^8.0.3",
    "@types/react": "^19.3.0",
    "@types/react-dom": "^19.3.0",
    "@vitejs/plugin-react": "^6.1.1",
    "typescript": "^5.9.0",
    "vite": "^8.3.2",
    "vitest": "^5.0.3"
  }
}
```
Run `cd frontend && npm install` to create `package-lock.json`. If npm reports a peer-dependency conflict (e.g. Apollo Client's supported `graphql` or `typescript` range), change only the conflicting package to the newest version npm accepts without `--force`/`--legacy-peer-deps`, and list the change in your report.

`frontend/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "skipLibCheck": true,
    "types": ["vite/client", "node"]
  },
  "include": ["src", "e2e", "vite.config.ts", "vitest.config.ts", "playwright.config.ts"]
}
```

`frontend/vite.config.ts`:
```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const rails = "http://localhost:3000";

export default defineConfig({
  base: "/console/",
  plugins: [react()],
  build: { outDir: "../public/console", emptyOutDir: true },
  server: {
    port: 5173,
    proxy: {
      "/session": rails,
      "/graphql": rails,
      "/cable": { target: "ws://localhost:3000", ws: true },
    },
  },
});
```

`frontend/vitest.config.ts`:
```ts
import { defineConfig } from "vitest/config";

export default defineConfig({ test: { include: ["src/**/*.test.ts"] } });
```

`frontend/index.html`:
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Timing console</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

`frontend/src/main.tsx`:
```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
```

`frontend/src/App.tsx` (placeholder; replaced in Task 2):
```tsx
export function App() {
  return <p>Timing console</p>;
}
```

`frontend/src/styles.css`:
```css
:root { font: 14px/1.4 system-ui, sans-serif; color: #1a1a1a; background: #f6f6f4; }
body { margin: 0; }
button { font: inherit; padding: 4px 10px; cursor: pointer; }
button:disabled { cursor: default; opacity: 0.5; }
input { font: inherit; padding: 3px 6px; }
.topbar { display: flex; gap: 12px; align-items: center; padding: 8px 16px; background: #222; color: #fff; }
.topbar a { color: #fff; }
.spacer { flex: 1; }
.page { padding: 16px; }
.race-screen { display: grid; grid-template-columns: 1fr 360px; gap: 16px; padding: 16px; align-items: start; }
.panel { background: #fff; border: 1px solid #ddd; border-radius: 6px; padding: 12px; margin-bottom: 12px; }
.panel h2, .panel h3 { margin: 0 0 8px; font-size: 15px; }
.groups { display: flex; gap: 8px; margin-bottom: 12px; }
.groups a { padding: 4px 10px; border: 1px solid #bbb; border-radius: 4px; text-decoration: none; color: inherit; }
.groups a.current { background: #222; color: #fff; }
.controls { display: flex; gap: 16px; align-items: center; flex-wrap: wrap; }
.go { font-size: 18px; font-weight: 700; padding: 6px 24px; background: #1d7a32; color: #fff; border: 0; border-radius: 4px; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: 3px 8px; border-bottom: 1px solid #eee; }
th { font-weight: 600; color: #555; }
.num { text-align: right; font-variant-numeric: tabular-nums; }
.error { color: #b00020; }
.warning { background: #fff4d6; border: 1px solid #e6c35c; padding: 6px 10px; border-radius: 4px; margin-bottom: 12px; }
.muted { color: #777; }
.queue li { list-style: none; padding: 8px 0; border-bottom: 1px solid #eee; }
.queue ul { padding: 0; margin: 0; }
.queue .actions { display: flex; gap: 6px; margin-top: 4px; align-items: center; }
.signin { max-width: 280px; margin: 80px auto; display: grid; gap: 8px; }
```

- [ ] **Step 2: Write failing tests for the helpers**

`frontend/src/route.test.ts`:
```ts
import { describe, expect, it } from "vitest";
import { eventHref, parseRoute } from "./route";

describe("parseRoute", () => {
  it("defaults to the event list", () => {
    expect(parseRoute("")).toEqual({ view: "events" });
    expect(parseRoute("#/")).toEqual({ view: "events" });
    expect(parseRoute("#/nonsense")).toEqual({ view: "events" });
  });

  it("reads an event and optional start group", () => {
    expect(parseRoute("#/events/e1")).toEqual({ view: "event", eventId: "e1", groupId: null });
    expect(parseRoute("#/events/e1/groups/g2")).toEqual({ view: "event", eventId: "e1", groupId: "g2" });
  });

  it("round-trips through eventHref", () => {
    expect(parseRoute(eventHref("a b", "c/d"))).toEqual({ view: "event", eventId: "a b", groupId: "c/d" });
    expect(eventHref("e1")).toBe("#/events/e1");
  });
});
```

`frontend/src/format.test.ts`:
```ts
import { describe, expect, it } from "vitest";
import { formatElapsed, formatGap } from "./format";

describe("formatElapsed", () => {
  it("formats minutes, seconds and tenths", () => {
    expect(formatElapsed(61_500)).toBe("1:01.5");
    expect(formatElapsed(0)).toBe("0:00.0");
    expect(formatElapsed(3_600_000)).toBe("1:00:00.0");
    expect(formatElapsed(59_960)).toBe("1:00.0");
  });

  it("is blank for missing values", () => {
    expect(formatElapsed(null)).toBe("");
    expect(formatElapsed(undefined)).toBe("");
  });
});

describe("formatGap", () => {
  it("shows laps down, else the time gap", () => {
    expect(formatGap(1, null)).toBe("-1 lap");
    expect(formatGap(2, null)).toBe("-2 laps");
    expect(formatGap(0, 40_000)).toBe("+0:40.0");
    expect(formatGap(null, null)).toBe("");
  });
});
```

`frontend/src/roles.test.ts`:
```ts
import { describe, expect, it } from "vitest";
import { canAct, isSignedOutError } from "./roles";

describe("canAct", () => {
  it("lets chiefs and admins act, not timers", () => {
    expect(canAct("chief")).toBe(true);
    expect(canAct("admin")).toBe(true);
    expect(canAct("timer")).toBe(false);
  });
});

describe("isSignedOutError", () => {
  it("recognises the API's sign-in errors", () => {
    expect(isSignedOutError(new Error("Sign in required"))).toBe(true);
    expect(isSignedOutError({ message: "Response not successful: Received status code 401" })).toBe(true);
    expect(isSignedOutError(new Error("Not found"))).toBe(false);
    expect(isSignedOutError(undefined)).toBe(false);
  });
});
```

- [ ] **Step 3: Run to verify failure**

Run: `cd frontend && npm test`
Expected: FAIL — cannot resolve `./route`, `./format`, `./roles`.

- [ ] **Step 4: Implement the helpers**

`frontend/src/route.ts`:
```ts
import { useEffect, useState } from "react";

export type Route = { view: "events" } | { view: "event"; eventId: string; groupId: string | null };

export function parseRoute(hash: string): Route {
  const parts = hash.replace(/^#\/?/, "").split("/").filter(Boolean);
  if (parts[0] === "events" && parts[1]) {
    const groupId = parts[2] === "groups" && parts[3] ? decodeURIComponent(parts[3]) : null;
    return { view: "event", eventId: decodeURIComponent(parts[1]), groupId };
  }
  return { view: "events" };
}

export function eventHref(eventId: string, groupId?: string | null): string {
  const base = `#/events/${encodeURIComponent(eventId)}`;
  return groupId ? `${base}/groups/${encodeURIComponent(groupId)}` : base;
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parseRoute(window.location.hash));
  useEffect(() => {
    const update = () => setRoute(parseRoute(window.location.hash));
    window.addEventListener("hashchange", update);
    return () => window.removeEventListener("hashchange", update);
  }, []);
  return route;
}
```

`frontend/src/format.ts`:
```ts
export function formatElapsed(ms: number | null | undefined): string {
  if (ms == null) return "";
  const tenths = Math.round(ms / 100);
  const totalSeconds = Math.floor(tenths / 10);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = `${String(totalSeconds % 60).padStart(2, "0")}.${tenths % 10}`;
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${seconds}` : `${minutes}:${seconds}`;
}

export function formatGap(lapsDown: number | null | undefined, ms: number | null | undefined): string {
  if (lapsDown && lapsDown > 0) return `-${lapsDown} lap${lapsDown === 1 ? "" : "s"}`;
  if (ms != null) return `+${formatElapsed(ms)}`;
  return "";
}

export function formatClock(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour12: false });
}
```

`frontend/src/roles.ts`:
```ts
export type Role = "timer" | "chief" | "admin";

export function canAct(role: Role): boolean {
  return role === "chief" || role === "admin";
}

export function isSignedOutError(error: unknown): boolean {
  const message = (error as { message?: string } | undefined)?.message ?? "";
  return message.includes("Sign in required") || message.includes("status code 401");
}
```

- [ ] **Step 5: Run tests, typecheck, build**

```bash
cd frontend && npm test && npm run typecheck && npm run build && ls ../public/console/index.html
```
Expected: all tests pass, no type errors, `public/console/index.html` exists.

- [ ] **Step 6: Rails-side build task, ignores, CI job**

`lib/tasks/console.rake`:
```ruby
namespace :console do
  desc "Install frontend dependencies and build the ops console into public/console"
  task :build do
    Dir.chdir(Rails.root.join("frontend")) { sh "npm ci && npm run build" }
  end
end
```

Append to `.gitignore`:
```
/public/console/
/frontend/node_modules/
/frontend/test-results/
/frontend/playwright-report/
```

Append this job to `.github/workflows/ci.yml` under `jobs:` (same indentation as `rails:`):
```yaml
  console:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: frontend
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: frontend/package-lock.json
      - run: npm ci
      - run: npm run typecheck
      - run: npm test
      - run: npm run build
```

Run: `bin/rails console:build`
Expected: npm ci + build succeed; `public/console/index.html` exists; `git status` does not list `public/console` or `frontend/node_modules`.

- [ ] **Step 7: Commit**

```bash
git add frontend .gitignore lib/tasks/console.rake .github/workflows/ci.yml
git commit -m "feat(console): frontend scaffold, routing/format/role helpers, CI job

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: App shell — sign in, event list, Playwright harness

**Files:**
- Create: `frontend/src/api.ts`, `frontend/src/session.ts`, `frontend/src/queries.ts` (events + me), `frontend/src/views/SignIn.tsx`, `frontend/src/views/Events.tsx`, `frontend/playwright.config.ts`, `frontend/e2e/seed.rb`, `frontend/e2e/sign-in.spec.ts`, `bin/e2e-server`
- Modify: `frontend/src/App.tsx`, `frontend/src/main.tsx`, `config/database.yml`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `useRoute`, `eventHref`, `isSignedOutError`, `canAct` (Task 1).
- Produces: `client` (Apollo); `Official` type, `currentOfficial()`, `signIn(name, pin)`, `signOut()`; `EVENTS` query + `EventsData`; `App` shell rendering `<Events>` or (Task 3) `<RaceScreen eventId groupId official onSignedOut>`; e2e harness (`bin/e2e-server`, seed with officials "E2E Chief"/2468 (chief) and "E2E Timer"/1357 (timer) and demo event "E2E CX" with 4 riders per race).

- [ ] **Step 1: E2E harness and failing sign-in test**

In `config/database.yml`, change the test database line to:
```yaml
  database: <%= sqlite ? ENV.fetch("TIMING_SQLITE_PATH", "storage/test.sqlite3") : "timing_test" %>
```

`bin/e2e-server` (then `chmod +x bin/e2e-server`):
```bash
#!/usr/bin/env bash
# Rails in the test environment, with its own SQLite file, serving the built
# console for Playwright. Recreated from scratch on every run.
set -euo pipefail
cd "$(dirname "$0")/.."
export RAILS_ENV=test TIMING_DB=sqlite3 TIMING_SQLITE_PATH=storage/e2e.sqlite3
rm -f storage/e2e.sqlite3*
bin/rails db:schema:load >/dev/null
bin/rails runner frontend/e2e/seed.rb
exec bin/rails server -p 3200 -b 127.0.0.1 -P tmp/pids/e2e.pid
```

`frontend/e2e/seed.rb`:
```ruby
# Seeds the Playwright database (see bin/e2e-server).
Official.create!(name: "E2E Chief", role: "chief", pin: "2468")
Official.create!(name: "E2E Timer", role: "timer", pin: "1357")
event = RaceSimulator::Demo.create!(riders_per_race: 4, name: "E2E CX")
puts "Seeded #{event.name} (#{event.id})"
```

`frontend/playwright.config.ts`:
```ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "e2e",
  timeout: 120_000,
  workers: 1,
  use: { baseURL: "http://127.0.0.1:3200", trace: "retain-on-failure" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "../bin/e2e-server",
    url: "http://127.0.0.1:3200/up",
    timeout: 180_000,
    reuseExistingServer: false,
  },
});
```

`frontend/e2e/sign-in.spec.ts`:
```ts
import { expect, test, type Page } from "@playwright/test";

async function signIn(page: Page, name: string, pin: string) {
  await page.goto("/console/");
  await page.getByLabel("Name").fill(name);
  await page.getByLabel("PIN").fill(pin);
  await page.getByRole("button", { name: "Sign in" }).click();
}

test("wrong PIN shows the API's error", async ({ page }) => {
  await signIn(page, "E2E Chief", "0000");
  await expect(page.getByText("Name or PIN is incorrect")).toBeVisible();
});

test("chief signs in, sees events, signs out", async ({ page }) => {
  await signIn(page, "E2E Chief", "2468");
  await expect(page.getByRole("link", { name: /E2E CX/ })).toBeVisible();
  await page.reload();
  await expect(page.getByRole("link", { name: /E2E CX/ })).toBeVisible();
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page.getByLabel("PIN")).toBeVisible();
});

// Review Focus 3
test("a timer sees the race screen without action buttons", async ({ page }) => {
  await signIn(page, "E2E Timer", "1357");
  await page.getByRole("link", { name: /E2E CX/ }).click();
  await expect(page.getByRole("heading", { name: "Review queue" })).toBeVisible();
  await expect(page.getByRole("button", { name: "GO" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Set laps" })).toHaveCount(0);
});
```

Install the browser and run: `cd frontend && npx playwright install chromium && npm run e2e`
Expected: FAIL — no "Name" field (the placeholder App).

The third test needs the race screen from Task 3. Until then mark it `test.fixme(...)` instead of `test(...)` and note that in your report; Task 3 turns it back on.

- [ ] **Step 2: Apollo client, session, queries**

`frontend/src/api.ts`:
```ts
import { ApolloClient, HttpLink, InMemoryCache } from "@apollo/client";

export const client = new ApolloClient({
  link: new HttpLink({ uri: "/graphql", credentials: "same-origin" }),
  cache: new InMemoryCache(),
});
```

`frontend/src/session.ts`:
```ts
import type { Role } from "./roles";

export type Official = { id: string; name: string; role: Role };

async function body(res: Response): Promise<Record<string, unknown>> {
  try {
    return (await res.json()) as Record<string, unknown>;
  } catch {
    return {};
  }
}

export async function currentOfficial(): Promise<Official | null> {
  const res = await fetch("/session", { credentials: "same-origin" });
  return res.ok ? ((await res.json()) as Official) : null;
}

export async function signIn(name: string, pin: string): Promise<Official> {
  const res = await fetch("/session", {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, pin }),
  });
  const data = await body(res);
  if (!res.ok) throw new Error(typeof data.error === "string" ? data.error : `Sign-in failed (${res.status})`);
  return data as unknown as Official;
}

export async function signOut(): Promise<void> {
  await fetch("/session", { method: "DELETE", credentials: "same-origin" });
}
```

`frontend/src/queries.ts`:
```ts
import { gql } from "@apollo/client";

export type EventSummary = { id: string; name: string; date: string };
export type EventsData = { events: EventSummary[] };

export const EVENTS = gql`
  query Events {
    events { id name date }
  }
`;
```

- [ ] **Step 3: Views and shell**

`frontend/src/views/SignIn.tsx`:
```tsx
import { useState, type FormEvent } from "react";
import { signIn, type Official } from "../session";

export function SignIn({ onSignedIn }: { onSignedIn: (official: Official) => void }) {
  const [name, setName] = useState("");
  const [pin, setPin] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      onSignedIn(await signIn(name.trim(), pin));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="signin" onSubmit={submit}>
      <h1>Timing console</h1>
      <label>
        Name
        <input value={name} onChange={(e) => setName(e.target.value)} autoFocus />
      </label>
      <label>
        PIN
        <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} />
      </label>
      <button type="submit" disabled={busy || !name || !pin}>Sign in</button>
      {error && <p className="error">{error}</p>}
    </form>
  );
}
```

`frontend/src/views/Events.tsx`:
```tsx
import { useQuery } from "@apollo/client/react";
import { useEffect } from "react";
import { EVENTS, type EventsData } from "../queries";
import { isSignedOutError } from "../roles";
import { eventHref } from "../route";

export function Events({ onSignedOut }: { onSignedOut: () => void }) {
  const { data, error, loading } = useQuery<EventsData>(EVENTS, { fetchPolicy: "network-only" });
  useEffect(() => {
    if (isSignedOutError(error)) onSignedOut();
  }, [error, onSignedOut]);

  return (
    <div className="page">
      <h1>Events</h1>
      {loading && <p className="muted">Loading…</p>}
      {error && <p className="error">{error.message}</p>}
      <ul>
        {data?.events.map((event) => (
          <li key={event.id}>
            <a href={eventHref(event.id)}>
              {event.name} — {event.date}
            </a>
          </li>
        ))}
      </ul>
      {data && data.events.length === 0 && <p className="muted">No events yet.</p>}
    </div>
  );
}
```

Replace `frontend/src/App.tsx`:
```tsx
import { useCallback, useEffect, useState } from "react";
import { client } from "./api";
import { useRoute } from "./route";
import { currentOfficial, signOut, type Official } from "./session";
import { Events } from "./views/Events";
import { SignIn } from "./views/SignIn";

export function App() {
  const [official, setOfficial] = useState<Official | null | undefined>(undefined);
  const route = useRoute();

  useEffect(() => {
    currentOfficial().then(setOfficial).catch(() => setOfficial(null));
  }, []);

  const signedOut = useCallback(() => {
    void client.clearStore();
    setOfficial(null);
  }, []);

  async function handleSignOut() {
    await signOut();
    signedOut();
  }

  if (official === undefined) return <p className="page muted">Loading…</p>;
  if (official === null) return <SignIn onSignedIn={setOfficial} />;

  return (
    <div>
      <header className="topbar">
        <a href="#/">Events</a>
        <span className="spacer" />
        <span>
          {official.name} ({official.role})
        </span>
        <button onClick={handleSignOut}>Sign out</button>
      </header>
      {route.view === "events" && <Events onSignedOut={signedOut} />}
      {route.view === "event" && <p className="page muted">Race screen comes in the next task.</p>}
    </div>
  );
}
```

Replace `frontend/src/main.tsx`:
```tsx
import { ApolloProvider } from "@apollo/client/react";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { client } from "./api";
import { App } from "./App";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ApolloProvider client={client}>
      <App />
    </ApolloProvider>
  </StrictMode>,
);
```

If Apollo Client 4 exposes `ApolloProvider`/`useQuery`/`useMutation` from a different path than `@apollo/client/react` in the installed version, use the path the installed package documents and list it in your report.

- [ ] **Step 4: Run e2e, unit, typecheck**

```bash
cd frontend && npm run e2e && npm test && npm run typecheck
```
Expected: the two active sign-in tests pass (the timer test is `fixme`); unit tests and typecheck pass.

- [ ] **Step 5: CI runs the e2e tests**

In the `console` job in `.github/workflows/ci.yml`, before `- run: npm ci` add:
```yaml
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
          working-directory: .
```
and after `- run: npm run build` add:
```yaml
      - run: npx playwright install --with-deps chromium
      - run: npm run e2e
```

- [ ] **Step 6: Commit**

```bash
git add frontend bin/e2e-server config/database.yml .github/workflows/ci.yml
git commit -m "feat(console): sign in, event list, Playwright harness against Rails

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Race screen — GO, lap count, standings, review queue, live refresh

**Files:**
- Create: `frontend/src/useEventChanges.ts`, `frontend/src/views/RaceScreen.tsx`, `frontend/src/views/GroupControls.tsx`, `frontend/src/views/Standings.tsx`, `frontend/src/views/ReviewQueue.tsx`, `frontend/e2e/simulate.rb`, `frontend/e2e/race.spec.ts`
- Modify: `frontend/src/queries.ts`, `frontend/src/App.tsx`, `frontend/e2e/sign-in.spec.ts` (un-`fixme` the timer test)

**Interfaces:**
- Consumes: `client`, `Official`, `canAct`, `isSignedOutError`, `eventHref`, `formatElapsed/Gap/Clock` (Tasks 1–2); API: `event(id)`, `standings(eventId)`, `rulings(eventId)`, mutations `fireStart`, `setLapCount`, `acceptSuggestion`, `dismissSuggestion`.
- Produces: `<RaceScreen eventId groupId official onSignedOut>`; `useEventChanges(eventId, onChange)`; DOM hooks used by e2e: suggestion items `data-testid="suggestion"`, status cells `data-testid="rider-status"`, labelled "Laps" input, buttons "GO", "Set laps", "Accept", "Dismiss", headings "Review queue".

- [ ] **Step 1: Failing race e2e test and simulator script**

`frontend/e2e/simulate.rb`:
```ruby
# Writes a simulated 3-lap race for "E2E CX" from the GO time the console
# recorded. Some taps have no bib, so the review queue has work to do.
event = Event.find_by!(name: "E2E CX")
group = event.start_groups.first
gun = Ruling.where(event:, kind: "set_group_start").order(:created_at_ms, :id).last&.payload&.fetch("at_ms")
abort "GO has not been pressed" unless gun
truths = RaceSimulator::Generator.new(races: RaceSimulator.specs_for(group), laps: 3,
                                      seed: Integer(ENV.fetch("SEED", "7")), untagged_rate: 0.5).call
untagged = truths.sum { it.untagged.size }
abort "seed produced no bib-less taps; pick another SEED" if untagged.zero?
RaceSimulator::Runner.new(writer: RaceSimulator::Writer.new(event:), gun_at_ms: gun, truths:).call
puts "Wrote #{RaceSimulator::Runner.taps(truths).size} taps (#{untagged} without a bib); " \
     "GO rulings: #{Ruling.where(event:, kind: 'set_group_start').count}"
```

`frontend/e2e/race.spec.ts`:
```ts
import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "../..");

function simulateRace(): string {
  return execFileSync("bin/rails", ["runner", "frontend/e2e/simulate.rb"], {
    cwd: repoRoot,
    env: { ...process.env, RAILS_ENV: "test", TIMING_DB: "sqlite3", TIMING_SQLITE_PATH: "storage/e2e.sqlite3" },
    encoding: "utf8",
  });
}

test("chief runs a simulated race and clears the review queue", async ({ page }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Chief");
  await page.getByLabel("PIN").fill("2468");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E CX/ }).click();

  await page.getByLabel("Laps").fill("3");
  await page.getByRole("button", { name: "Set laps" }).click();
  await expect(page.getByText("3 laps").first()).toBeVisible();

  // Review Focus 1: a double-click must record one start.
  await page.getByRole("button", { name: "GO" }).dblclick();
  await expect(page.getByText(/Started at/)).toBeVisible();
  await expect(page.getByRole("button", { name: "GO" })).toHaveCount(0);

  const output = simulateRace();
  expect(output).toContain("GO rulings: 1");

  const missed = page.getByTestId("suggestion").filter({ hasText: "missed crossing" });
  await expect(missed.first()).toBeVisible({ timeout: 20_000 });
  for (let remaining = await missed.count(); remaining > 0; remaining--) {
    await missed.first().getByRole("button", { name: "Accept" }).click();
    await expect(missed).toHaveCount(remaining - 1, { timeout: 20_000 });
  }

  await expect(page.getByTestId("suggestion")).toHaveCount(0, { timeout: 20_000 });
  const statuses = page.getByTestId("rider-status");
  await expect(statuses).toHaveCount(12);
  await expect(statuses.filter({ hasNotText: "finished" })).toHaveCount(0);
});
```

In `frontend/e2e/sign-in.spec.ts`, change the timer test back from `test.fixme(` to `test(`.

Run: `cd frontend && npm run e2e`
Expected: FAIL — the race screen placeholder has no "Laps" field.

- [ ] **Step 2: Queries and types**

Append to `frontend/src/queries.ts`:
```ts
export type RaceInfo = { id: string; name: string };
export type StartGroupInfo = { id: string; name: string; finishRule: { type: string }; races: RaceInfo[] };
export type EventData = { event: { id: string; name: string; startGroups: StartGroupInfo[] } };

export const EVENT = gql`
  query Event($id: ID!) {
    event(id: $id) {
      id
      name
      startGroups { id name finishRule races { id name } }
    }
  }
`;

export type Row = {
  place: number | null;
  bib: string;
  name: string;
  status: string;
  laps: number;
  elapsedMs: number | null;
  gapLapsDown: number | null;
  gapMs: number | null;
};
export type RaceStandings = { race: { id: string; name: string }; state: string; lapCount: number | null; rows: Row[] };
export type Suggestion = { key: string; kind: string; bib: string | null; message: string; needs: string[] };
export type StandingsData = {
  standings: { stale: boolean; error: string | null; races: RaceStandings[]; suggestions: Suggestion[] };
};

export const STANDINGS = gql`
  query Standings($eventId: ID!) {
    standings(eventId: $eventId) {
      stale
      error
      races {
        race { id name }
        state
        lapCount
        rows { place bib name status laps elapsedMs gapLapsDown gapMs }
      }
      suggestions { key kind bib message needs }
    }
  }
`;

export type RulingsData = { rulings: { id: string; kind: string; payload: Record<string, unknown>; reverted: boolean }[] };

export const RULINGS = gql`
  query Rulings($eventId: ID!) {
    rulings(eventId: $eventId) { id kind payload reverted }
  }
`;

export type MutationResult = { errors: string[] };

export const FIRE_START = gql`
  mutation FireStart($startGroupId: ID!) { fireStart(startGroupId: $startGroupId) { errors } }
`;
export const SET_LAP_COUNT = gql`
  mutation SetLapCount($startGroupId: ID!, $laps: Int!) { setLapCount(startGroupId: $startGroupId, laps: $laps) { errors } }
`;
export const ACCEPT_SUGGESTION = gql`
  mutation AcceptSuggestion($eventId: ID!, $key: String!, $bib: String) {
    acceptSuggestion(eventId: $eventId, key: $key, bib: $bib) { errors }
  }
`;
export const DISMISS_SUGGESTION = gql`
  mutation DismissSuggestion($eventId: ID!, $key: String!) { dismissSuggestion(eventId: $eventId, key: $key) { errors } }
`;
```

- [ ] **Step 3: Live updates hook**

`frontend/src/useEventChanges.ts`:
```ts
import { createConsumer } from "@rails/actioncable";
import { useEffect, useRef } from "react";

const consumer = createConsumer("/cable");

// Calls onChange (debounced) whenever the hub says the event changed.
export function useEventChanges(eventId: string, onChange: () => void): void {
  const latest = useRef(onChange);
  latest.current = onChange;

  useEffect(() => {
    let timer: number | undefined;
    const subscription = consumer.subscriptions.create(
      { channel: "EventChannel", event_id: eventId },
      {
        received() {
          window.clearTimeout(timer);
          timer = window.setTimeout(() => latest.current(), 300);
        },
      },
    );
    return () => {
      window.clearTimeout(timer);
      subscription.unsubscribe();
    };
  }, [eventId]);
}
```

- [ ] **Step 4: Views**

`frontend/src/views/Standings.tsx`:
```tsx
import { formatElapsed, formatGap } from "../format";
import type { RaceStandings } from "../queries";

const STATE_LABEL: Record<string, string> = { NOT_STARTED: "not started", IN_PROGRESS: "in progress", FINISH_OPEN: "finish open" };

export function Standings({ race }: { race: RaceStandings }) {
  return (
    <section className="panel" aria-label={race.race.name}>
      <h3>
        {race.race.name} — {STATE_LABEL[race.state] ?? race.state} — {race.lapCount ? `${race.lapCount} laps` : "lap count not set"}
      </h3>
      <table>
        <thead>
          <tr>
            <th className="num">#</th>
            <th>Bib</th>
            <th>Name</th>
            <th>Status</th>
            <th className="num">Laps</th>
            <th className="num">Time</th>
            <th className="num">Gap</th>
          </tr>
        </thead>
        <tbody>
          {race.rows.map((row) => (
            <tr key={row.bib}>
              <td className="num">{row.place ?? "–"}</td>
              <td>{row.bib}</td>
              <td>{row.name}</td>
              <td data-testid="rider-status">{row.status.toLowerCase()}</td>
              <td className="num">{row.laps}</td>
              <td className="num">{formatElapsed(row.elapsedMs)}</td>
              <td className="num">{formatGap(row.gapLapsDown, row.gapMs)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
```

`frontend/src/views/GroupControls.tsx`:
```tsx
import { useMutation } from "@apollo/client/react";
import { useRef, useState, type FormEvent } from "react";
import { formatClock } from "../format";
import { FIRE_START, SET_LAP_COUNT, type MutationResult } from "../queries";

type Props = {
  groupId: string;
  started: boolean;
  startedAtMs: number | null;
  lapCount: number | null;
  canAct: boolean;
  onChanged: () => void;
};

export function GroupControls({ groupId, started, startedAtMs, lapCount, canAct, onChanged }: Props) {
  const [fireStart] = useMutation<{ fireStart: MutationResult }>(FIRE_START);
  const [setLapCount] = useMutation<{ setLapCount: MutationResult }>(SET_LAP_COUNT);
  const [firing, setFiring] = useState(false);
  const firingRef = useRef(false); // a ref, so a double-click's second event sees it immediately
  const [laps, setLaps] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function go() {
    if (firingRef.current) return; // one GO per click burst (Review Focus 1)
    firingRef.current = true;
    setFiring(true);
    setError(null);
    try {
      const { data } = await fireStart({ variables: { startGroupId: groupId } });
      const errors = data?.fireStart.errors ?? [];
      if (errors.length) {
        setError(errors.join("; "));
        firingRef.current = false;
        setFiring(false);
      }
    } catch (e) {
      setError((e as Error).message);
      firingRef.current = false;
      setFiring(false);
    }
    onChanged();
  }

  async function submitLaps(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      const { data } = await setLapCount({ variables: { startGroupId: groupId, laps: Number(laps) } });
      const errors = data?.setLapCount.errors ?? [];
      if (errors.length) setError(errors.join("; "));
      else setLaps("");
    } catch (e) {
      setError((e as Error).message);
    }
    onChanged();
  }

  return (
    <div className="panel controls">
      {started ? (
        <strong>Started at {startedAtMs ? formatClock(startedAtMs) : "—"}</strong>
      ) : canAct ? (
        <button className="go" onClick={go} disabled={firing}>GO</button>
      ) : (
        <span className="muted">Not started</span>
      )}
      <span>Lap count: {lapCount ?? "not set"}</span>
      {canAct && (
        <form onSubmit={submitLaps} className="controls">
          <label>
            Laps <input type="number" min={1} value={laps} onChange={(e) => setLaps(e.target.value)} style={{ width: 64 }} />
          </label>
          <button type="submit" disabled={!laps}>Set laps</button>
        </form>
      )}
      {error && <span className="error">{error}</span>}
    </div>
  );
}
```

`frontend/src/views/ReviewQueue.tsx`:
```tsx
import { useMutation } from "@apollo/client/react";
import { useState } from "react";
import { ACCEPT_SUGGESTION, DISMISS_SUGGESTION, type MutationResult, type Suggestion } from "../queries";

type Props = { eventId: string; suggestions: Suggestion[]; canAct: boolean; onChanged: () => void };

export function ReviewQueue({ eventId, suggestions, canAct, onChanged }: Props) {
  return (
    <aside className="panel queue">
      <h2>Review queue ({suggestions.length})</h2>
      {suggestions.length === 0 && <p className="muted">Nothing to review.</p>}
      <ul>
        {suggestions.map((s) => (
          <SuggestionItem key={s.key} eventId={eventId} suggestion={s} canAct={canAct} onChanged={onChanged} />
        ))}
      </ul>
    </aside>
  );
}

function SuggestionItem({ eventId, suggestion, canAct, onChanged }: { eventId: string; suggestion: Suggestion; canAct: boolean; onChanged: () => void }) {
  const [accept] = useMutation<{ acceptSuggestion: MutationResult }>(ACCEPT_SUGGESTION);
  const [dismiss] = useMutation<{ dismissSuggestion: MutationResult }>(DISMISS_SUGGESTION);
  const [bib, setBib] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const needsBib = suggestion.needs.includes("bib");
  const needsCrossing = suggestion.needs.includes("capture_id");

  async function run(action: () => Promise<string[]>) {
    setBusy(true);
    setError(null);
    try {
      const errors = await action();
      if (errors.length) setError(errors.join("; "));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
      onChanged(); // refresh even on error: someone else may have handled it (Review Focus 4)
    }
  }

  const onAccept = () =>
    run(async () => {
      const { data } = await accept({ variables: { eventId, key: suggestion.key, bib: needsBib ? bib.trim() : null } });
      return data?.acceptSuggestion.errors ?? [];
    });
  const onDismiss = () =>
    run(async () => {
      const { data } = await dismiss({ variables: { eventId, key: suggestion.key } });
      return data?.dismissSuggestion.errors ?? [];
    });

  return (
    <li data-testid="suggestion">
      <div>{suggestion.message}</div>
      {canAct && (
        <div className="actions">
          {needsBib && <input aria-label="Bib" placeholder="Bib" value={bib} onChange={(e) => setBib(e.target.value)} style={{ width: 70 }} />}
          {!needsCrossing && (
            <button onClick={onAccept} disabled={busy || (needsBib && !bib.trim())}>Accept</button>
          )}
          <button onClick={onDismiss} disabled={busy}>Dismiss</button>
          {needsCrossing && <span className="muted">needs a crossing — not available yet</span>}
        </div>
      )}
      {error && <div className="error">{error}</div>}
    </li>
  );
}
```

`frontend/src/views/RaceScreen.tsx`:
```tsx
import { useQuery } from "@apollo/client/react";
import { useCallback, useEffect } from "react";
import { EVENT, RULINGS, STANDINGS, type EventData, type RulingsData, type StandingsData } from "../queries";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import { eventHref } from "../route";
import type { Official } from "../session";
import { useEventChanges } from "../useEventChanges";
import { GroupControls } from "./GroupControls";
import { ReviewQueue } from "./ReviewQueue";
import { Standings } from "./Standings";

type Props = { eventId: string; groupId: string | null; official: Official; onSignedOut: () => void };

export function RaceScreen({ eventId, groupId, official, onSignedOut }: Props) {
  const event = useQuery<EventData>(EVENT, { variables: { id: eventId } });
  const standings = useQuery<StandingsData>(STANDINGS, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });
  const rulings = useQuery<RulingsData>(RULINGS, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });

  const refresh = useCallback(() => {
    void standings.refetch();
    void rulings.refetch();
  }, [standings, rulings]);
  useEventChanges(eventId, refresh);

  const firstError = event.error ?? standings.error ?? rulings.error;
  useEffect(() => {
    if (isSignedOutError(firstError)) onSignedOut();
  }, [firstError, onSignedOut]);

  const groups = event.data?.event.startGroups ?? [];
  const group = groups.find((g) => g.id === groupId) ?? groups[0];
  if (!event.data) return <p className="page muted">{event.error ? event.error.message : "Loading…"}</p>;
  if (!group) return <p className="page muted">This event has no start groups.</p>;

  const raceIds = new Set(group.races.map((r) => r.id));
  const report = standings.data?.standings;
  const races = report?.races.filter((r) => raceIds.has(r.race.id)) ?? [];
  const started = races.some((r) => r.state !== "NOT_STARTED");
  const start = rulings.data?.rulings.find(
    (r) => r.kind === "set_group_start" && !r.reverted && r.payload.start_group_id === group.id,
  );
  const canAct = roleCanAct(official.role);

  return (
    <div className="race-screen">
      <main>
        <h1>{event.data.event.name}</h1>
        <nav className="groups">
          {groups.map((g) => (
            <a key={g.id} href={eventHref(eventId, g.id)} className={g.id === group.id ? "current" : ""}>
              {g.name}
            </a>
          ))}
        </nav>
        {(standings.error || rulings.error) && <p className="error">{(standings.error ?? rulings.error)!.message}</p>}
        {report?.stale && <p className="warning">Standings are out of date: {report.error}</p>}
        <GroupControls
          key={group.id}
          groupId={group.id}
          started={started}
          startedAtMs={typeof start?.payload.at_ms === "number" ? start.payload.at_ms : null}
          lapCount={races[0]?.lapCount ?? null}
          canAct={canAct}
          onChanged={refresh}
        />
        {races.map((race) => (
          <Standings key={race.race.id} race={race} />
        ))}
      </main>
      <ReviewQueue eventId={eventId} suggestions={report?.suggestions ?? []} canAct={canAct} onChanged={refresh} />
    </div>
  );
}
```

In `frontend/src/App.tsx`, import `RaceScreen` and replace the placeholder line for `route.view === "event"` with:
```tsx
      {route.view === "event" && (
        <RaceScreen eventId={route.eventId} groupId={route.groupId} official={official} onSignedOut={signedOut} />
      )}
```

- [ ] **Step 5: Run everything**

```bash
cd frontend && npm run e2e && npm test && npm run typecheck
```
Expected: all three e2e files pass (wrong PIN, sign in/out, timer view, race), unit tests and typecheck pass. If the race test fails because the seed produced unexpected suggestions, report their messages; do not loosen the assertions. If `SEED=7` produces no bib-less taps, choose another seed in `simulate.rb`'s default and say so.

- [ ] **Step 6: Commit**

```bash
git add frontend
git commit -m "feat(console): race screen with GO, lap count, standings, review queue, live refresh

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Serve the console from the hub; dev script; runbook

**Files:**
- Create: `bin/console-dev`
- Modify: `bin/hub`, `docs/hub-runbook.md`

**Interfaces:**
- Consumes: `console:build` (Task 1).
- Produces: `bin/hub` builds the console when `public/console/index.html` is missing; `bin/console-dev` runs Rails + Vite for development.

- [ ] **Step 1: bin/hub builds the console if needed**

In `bin/hub`, directly before the `exec` line, add:
```bash
[ -f public/console/index.html ] || bin/rails console:build
```

- [ ] **Step 2: Dev script**

`bin/console-dev` (then `chmod +x bin/console-dev`):
```bash
#!/usr/bin/env bash
# Rails API on :3000 plus the Vite dev server on :5173.
# Open http://localhost:5173/console/ (hot reload).
set -euo pipefail
cd "$(dirname "$0")/.."
export TIMING_ALLOWED_ORIGINS="http://localhost:5173"
bin/rails server -p 3000 &
rails_pid=$!
trap 'kill $rails_pid' EXIT
(cd frontend && npm run dev)
```

- [ ] **Step 3: Runbook**

Add to `docs/hub-runbook.md`, after the "At the venue (HTTPS)" section:
````markdown
## Ops console

- At the venue: `bin/hub` builds the console the first time and serves it at
  `https://<hub address>:3443/console/`. After pulling new code, rebuild with
  `bin/rails console:build`.
- In development: `bin/console-dev`, then open `http://localhost:5173/console/`.
  Simulated races (`bin/simulate-race`) show up within 5 seconds — the console
  also polls, because in development live pushes only reach the server process
  that made the change.
- Browser tests: `cd frontend && npm run e2e` (uses its own database, `storage/e2e.sqlite3`).
````

- [ ] **Step 4: Verify by hand**

```bash
bin/rails console:build
PORT=3100 HUB_TLS_PORT=3543 bin/hub &   # wait for "Listening on ssl://0.0.0.0:3543"
curl -s --cacert storage/certs/root-ca.crt https://localhost:3543/console/ -o /dev/null -w "console %{http_code}\n"
curl -s http://localhost:3100/console/ -o /dev/null -w "plain http console %{http_code}\n"
kill %1
```
Expected: `console 200`, `plain http console 403`. Make sure nothing is left listening on 3100/3543. Paste the output into the report.

- [ ] **Step 5: Commit**

```bash
git add bin/hub bin/console-dev docs/hub-runbook.md
git commit -m "feat(console): serve from the hub, dev script, runbook

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Coverage map (spec → task)

| Console v1 spec | Task |
|---|---|
| §3.1 sign in / out | 2 |
| §3.2 event list | 2 |
| §3.3 start group picker, GO (only before start), lap count, standings, review queue with bib field, crossing-needing suggestions dismiss-only, inline errors, stale banner | 3 |
| §3.4 live refresh (cable + 5 s poll) | 3 |
| §2 action buttons chief+ only | 1 (canAct), 2–3 |
| §5 `frontend/`, Vite, no router, hand-written types, `/console/` from `public/console`, `console:build`, `bin/hub`, dev proxy + `bin/console-dev` | 1, 2, 4 |
| §6 error handling, return to sign-in | 1 (isSignedOutError), 2, 3 |
| §7 Vitest, Playwright e2e, CI job | 1, 2, 3 |

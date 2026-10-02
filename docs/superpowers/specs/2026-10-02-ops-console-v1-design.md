# Ops Console v1 — Design

**Date:** 2026-10-02
**Status:** Draft for review
**Parent spec:** `docs/superpowers/specs/2026-10-01-hub-mvp-design.md` (§6 ops console)
**Approach:** start small and iterate. v1 is the smallest console that runs one race
from the browser; everything else waits until it's needed.

## 1. Goal

A chief official at the finish line, on the hub laptop, can sign in, pick an event
and start group, press GO, set the lap count, watch standings update during a
(simulated) race, and clear the review queue.

**Done when:** an automated browser test signs in, presses GO on a demo start group,
lets the simulator write a race that includes bib-less taps, accepts the missed-crossing
suggestions from the review queue, and then sees an empty review queue and every
rider in the start group listed as FINISHED in their race's standings.

## 2. Users and device

- One chief (or admin) official on a **laptop**: desktop layout, mouse and keyboard.
  No touch or phone layout.
- Timers can sign in and view, but action buttons (GO, lap count, accept, dismiss)
  are shown only to chief and above.

## 3. In v1

1. **Sign in / sign out** with name and PIN (`POST/DELETE /session`). Errors shown
   as returned ("Name or PIN is incorrect", rate-limit message).
2. **Event list**: name and date; click to open.
3. **Race screen** for one event:
   - **Start group picker** (the event's start groups).
   - For the selected group:
     - **GO** — shown only while the group's races are `NOT_STARTED`; once started,
       the screen shows the start time instead (no second GO from the UI in v1).
     - **Lap count** — current value (or "not set" for timed groups) and a number
       field + Set button (`setLapCount`).
     - **Standings** for each race in the group: place, bib, name, status, laps,
       elapsed, gap. Race state and lap count in each race's header.
   - **Review queue** (whole event): each suggestion's message, with **Accept** and
     **Dismiss**. If a suggestion `needs` a bib, Accept shows a small bib field first.
     Suggestions that need a crossing (`capture_id`) can only be dismissed in v1.
     Errors from Accept are shown inline (e.g. "no longer open").
   - **Stale banner** when standings are stale (`stale: true` + `error`).
4. **Live refresh**: subscribe to `EventChannel`; on `{"type":"changed"}` refetch
   standings (debounced ~300 ms). Also refetch every **5 s** as a safety net — the
   development and test cable adapters only deliver within one process, so changes
   written by the simulator wouldn't arrive otherwise.

## 4. Not in v1 (later, as needed)

Setup forms and CSV import in the UI · officials screen · devices screen and QR
pairing · two start groups side by side · rulings on a specific crossing (void,
reassign, flag finish, pull, DNF) · ruling history and revert · publishing ·
API changes from `docs/TODO.md` (crossing ids, re-fire guard, session expiry,
pairing URL) · GraphQL code generation · multi-package frontend workspace.

## 5. Architecture

- **`frontend/`**: one Vite app, React + TypeScript + Apollo Client + `@rails/actioncable`.
  npm (no workspace). No router library: three views selected from a small URL-hash
  route (`#/`, `#/events/:id`, `#/events/:id/groups/:groupId`) so reloads keep place
  and no server-side fallback route is needed.
- **GraphQL types**: hand-written TypeScript types next to each query for v1
  (code generation deferred).
- **Served by the hub**: `vite build` with base `/console/` writes to
  `public/console/` (git-ignored). Rails serves it as static files; the console is at
  `/console/`. A rake task `console:build` runs `npm ci` + build; `bin/hub` runs it
  when `public/console/index.html` is missing.
- **Development**: `npm run dev` (Vite, port 5173) proxies `/session`, `/graphql` and
  `/cable` to Rails on 3000. Rails must allow the dev origin:
  `TIMING_ALLOWED_ORIGINS=http://localhost:5173` (a `bin/console-dev` script sets it
  and starts both).
- **No API changes** unless the browser test exposes a blocker.

## 6. Error handling

- Network or GraphQL errors: a non-blocking error line at the top of the affected
  panel; data keeps showing.
- Signed out (session expired / 401 / "Sign in required"): return to sign-in.
- Mutation `errors` arrays shown next to the control that caused them.

## 7. Testing

- **Vitest** for small pure helpers (hash routing, time formatting, which actions a
  role sees).
- **Playwright** end-to-end test (the "done when" in §1) against Rails in the test
  environment with the built console: a seed script creates a chief official and a
  demo event; after GO, a runner script writes a simulated race (with bib-less taps)
  using the race simulator; the test waits for the 5 s refresh, accepts suggestions,
  and checks standings.
- **CI**: a frontend job — `npm ci`, typecheck, Vitest, build, Playwright (Chromium).
- Existing Rails, engine and packwerk checks unchanged.

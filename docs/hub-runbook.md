# Running the hub

## First time on a laptop

```bash
bin/rails db:prepare
NAME="Your Name" bin/rails access:bootstrap   # prints the admin PIN
```

## Development (HTTP on port 3000)

```bash
bin/rails server
```

## At the venue (HTTPS)

```bash
bin/hub
```

`bin/hub` sets `TIMING_MODE=hub HUB_TLS=1`, runs `db:prepare` and `hub:certs`, then starts puma directly with `bundle exec puma -C config/puma.rb`. It does not use `rails server`, which dropped the TLS bind.

- HTTPS on port 3443 (`HUB_TLS_PORT`) with the hub's own certificate (`storage/certs/`).
- Plain HTTP on `PORT` (default 3000) is for onboarding only: it serves `/onboarding` (tablets download and trust the hub certificate there, once) and `/up`.
- Before trusting the CA, crews should compare the root CA fingerprint shown on the onboarding page with the one printed by `bin/rails hub:certs`. They must match.
- `bin/hub` currently runs in the development environment, not production. See `docs/TODO.md`, "Run the venue hub in production mode".
- Keep `storage/` backed up: it holds the database and the certificate authority. A new CA means re-trusting every tablet.

## Ops console

- Building the console needs Node 24 and npm, and network access for `npm ci` —
  build it before you leave for the venue (`bin/rails console:build`). If the build
  fails, `bin/hub` warns and still starts; timing works, the console doesn't.
- At the venue: `bin/hub` builds the console the first time and serves it at
  `https://<hub address>:3443/console/`. After pulling new code, rebuild with
  `bin/rails console:build`.
- In development: `bin/console-dev`, then open `http://localhost:5173/console/`.
  Simulated races (`bin/simulate-race`) show up within 5 seconds — the console
  also polls, because in development live pushes only reach the server process
  that made the change.
- Browser tests: `cd frontend && npm run e2e` (uses its own database, `storage/e2e.sqlite3`).

## Watch a simulated race

```bash
bin/simulate-race --demo                  # 20× real time; --speed 0 writes it all at once
bin/rails hub:standings EVENT=<id> WATCH=1
```

## Replay a real race

```bash
bin/replay-race                           # Cross Crusade Cascade Locks 1: 34 races, 219 racers, real bibs
bin/replay-race --speed 60                # the whole day in about 6 minutes, to watch it live
bin/replay-race --check <event id>        # compare the hub's results with the published ones
bin/replay-race --dataset cascade_locks_2 # the second race (191 racers)
```

To add a race: `script/results-pdf-to-csv results.pdf > lib/race_simulator/data/<name>/results.csv`
(RaceResult-style PDFs; it undoes the shifted-glyph encoding some of them have), write
`waves.yml` with the event details and the schedule's waves (gun, minutes, race names),
then `bin/replay-race --dataset <name> --fit` prints it back with each wave's arming delay,
start offsets and flag time estimated from the results.

The data is in `lib/race_simulator/data/cascade_locks_1/`: `results.csv` (from the
published results PDF) and `waves.yml` (the schedule's waves, each race's start offset
the delay before the timing system was armed — estimates, edit freely — and when each
wave's finish flag came out, fitted to the results). Each wave's lap count is its
leader's. The check should report 3 riders who rode on after the flag (#386, and juniors
#70 and #324; #386's lost lap moves eight riders up a place) and 7 riders who quit early,
whom a chief marks DNF. Race 2 leaves 3 riders (#330, and #46 and #472 with impossibly
short last laps after the flag) and 6 who quit early.

## Course events

For a point-to-point or single-loop race (gravel, ultra), set the format to Course and add the
checkpoints (name, distance, optional cutoff) and the finish distance on the Event screen. Pair each
aid-station phone with its checkpoint (or pick it on the phone); the chief can move phones to another
checkpoint on the Devices screen. Results shows each rider's splits; the Course view shows how many
have passed each point and who is still out. Problems flags a missed checkpoint, an overdue rider and a
missed cutoff.

For a demo course event: `bin/replay-race --dataset gravel_demo`.

## API

- `POST /session` with `{"name": "...", "pin": "..."}` signs in (session cookie).
- `POST /graphql` — queries: `me`, `events`, `event(id)`, `categories`, `officials`, `standings(eventId)`, `rulings(eventId)`, `devices(eventId)`.
- `/cable` — `EventChannel` with `event_id`; `{"type":"changed"}` means refetch.
- `POST /devices/pair` with `{"token": "...", "name": "..."}` pairs a tablet (token from `createPairingToken`).

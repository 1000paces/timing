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

## Watch a simulated race

```bash
bin/simulate-race --demo                  # 20× real time; --speed 0 writes it all at once
bin/rails hub:standings EVENT=<id> WATCH=1
```

## API

- `POST /session` with `{"name": "...", "pin": "..."}` signs in (session cookie).
- `POST /graphql` — queries: `me`, `events`, `event(id)`, `categories`, `officials`, `standings(eventId)`, `rulings(eventId)`, `devices(eventId)`.
- `/cable` — `EventChannel` with `event_id`; `{"type":"changed"}` means refetch.
- `POST /devices/pair` with `{"token": "...", "name": "..."}` pairs a tablet (token from `createPairingToken`).

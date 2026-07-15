# local-run

Runs the upstream Chatwoot production compose file locally for debugging, with
operational overrides applied as a compose override layer instead of edits to
the upstream file.

The Kubernetes deployment in this repository is the real target; this exists
only for local inspection of the application's runtime behavior.

## Usage

```bash
# one-time: prepare the database before the first start
./up.sh migrate

# start / manage the stack
./up.sh          # up -d
./up.sh ps
./up.sh logs -f rails
./up.sh down
```

Runtime configuration (including credentials) comes from the `.env` file in
the Chatwoot checkout, which is ignored by Git there and is never committed
anywhere. Set `CHATWOOT_DIR` if the checkout is not at `~/playground/chatwoot`.

## What the override changes

- PostgreSQL and Redis host port publishing is removed (`!reset`): containers
  reach them by service name over the compose network; publishing them on the
  host only causes port collisions.
- `POSTGRES_PASSWORD` is interpolated from `.env` instead of the upstream
  hardcoded empty value, which PostgreSQL refuses to initialize with.

# Zero replica crashes on a deferred unique constraint

Postgres lets you defer a UNIQUE constraint check until COMMIT. That's the whole point of `DEFERRABLE INITIALLY DEFERRED`. Zero replicates the constraint to its SQLite replica via `CREATE UNIQUE INDEX`, which SQLite enforces on every statement. So any postgres transaction that produces a transient duplicate (a swap is the simplest case) commits fine in postgres but blows up the Zero write-worker on the first per-row apply.

## Run it

```
docker compose up -d
docker compose logs -f zero-cache  # wait for initial sync
docker exec -i $(docker compose ps -q postgres) \
  psql -U postgres -d zero_repro < trigger.sql
docker compose logs zero-cache | grep -E 'ERROR|UNIQUE'
```

Postgres returns `BEGIN`, `UPDATE 1`, `UPDATE 1`, `COMMIT`. Zero logs:

```
SqliteError: UNIQUE constraint failed: swap_test.workspace_id, swap_test.user_id, swap_test.target_id
  at TransactionProcessor.processUpdate
...
stopping IncrementalSyncer
```

It then retries the same UPDATE forever.

## What's in the box

`init.sql` creates `swap_test` with a deferred unique on `(workspace_id, user_id, target_id)` and seeds two rows.

`trigger.sql` runs two UPDATEs in one transaction that swap `target_id` between the rows. Mid-transaction both rows briefly share `target_id=300`. Postgres defers the check, COMMIT clears it. SQLite checks immediately and rejects the first UPDATE.

## What happened to us

A single transaction matching this shape (a `MERGE` that swapped a value across two rows under a deferred unique) put `zero-cache` and `zero-cache-rm` into a ~60-restart loop. After about 25 hours the postgres slot was invalidated for exceeding `max_slot_wal_keep_size`, which fired `AutoResetSignal` and forced a full initial-sync of every replicated table. The downstream view-syncer also stayed unhealthy because it loops on `Unable to reserve snapshot` against the unreachable rm instead of serving stale data from its own replica.

## Possible fixes

Two options from the outside; I'd guess A is the quick patch and B is closer to what postgres itself does.

Option A: skip the `UNIQUE` keyword when emitting the index for a deferred constraint. The `isImmediate` flag is already plumbed through to `services/change-source/pg/change-source.ts`. Filtering at `db/create.ts:createLiteIndexStatement` would do it. Replica gives up enforcement on these indexes; postgres is still source of truth.

Option B: skip-and-retry on `SQLITE_CONSTRAINT_UNIQUE` within a transaction batch. If a per-row apply fails, defer it, finish the rest of the batch, retry deferred ones at end. Since postgres already committed the transaction, the final state must be valid against every constraint on both sides, so retries terminate. Keeps replica enforcement.

## Versions

- `postgres:18-alpine`
- `rocicorp/zero:1.6.0-canary.12`

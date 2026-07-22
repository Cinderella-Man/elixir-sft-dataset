# Deduplicating Dead Letter Queue

Write me an Elixir GenServer module called `DedupDLQ` — a dead letter queue that **coalesces** repeated failures of the same logical message. Instead of storing a new entry every time the same failure recurs, it keeps a single entry per **dedup key** and counts how many times that failure has been observed.

## Public API

- `DedupDLQ.start_link(opts)` starts the process.
  - `:clock` — a zero-arity function returning the current time in **milliseconds**. Default `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional process registration name.

- `DedupDLQ.push(server, queue_name, dedup_key, message, error_reason, metadata)` records a failure under a dedup key within the queue.
  - If no entry exists for `dedup_key` in the queue: create one with `occurrences` `1`, `retry_count` `0`, and both `first_seen` and `last_seen` set to the current time. Return `{:ok, :new, message_id}` with a server-unique id.
  - If an entry already exists for `dedup_key`: increment its `occurrences`, update `last_seen` to now, and overwrite its `message`, `error_reason`, and `metadata` with the newly supplied (latest) values, while preserving its id, `first_seen`, and `retry_count`. Return `{:ok, :duplicate, existing_message_id}`.

- `DedupDLQ.peek(server, queue_name, count)` returns up to `count` entries, ordered **oldest-first by `first_seen`**, without removing them. Each entry includes at least `:id`, `:dedup_key`, `:message`, `:error_reason`, `:metadata`, `:occurrences`, `:retry_count`, `:first_seen`, and `:last_seen`. Unknown/empty queue → `[]`.

- `DedupDLQ.retry(server, queue_name, dedup_key, handler_fn)` re-attempts one coalesced message by its dedup key.
  - Missing key → `{:error, :not_found}`.
  - Invoke `handler_fn.(message)` with the stored message. Success (`:ok` / `{:ok, term}`) removes the entry and returns `:ok`.
  - Failure (`{:error, reason}`, any other return, or a raised/thrown exception — any `{:error, _}` reason acceptable) keeps the entry, increments its `retry_count` by 1, and returns `{:error, reason}`. A failing/raising handler must not crash the process.

- `DedupDLQ.purge(server, queue_name, older_than)` removes stale entries by **recency of the last observation**: an entry is removed when `now - last_seen >= older_than` (age in ms). Returns `{:ok, purged_count}`. (Re-pushing a duplicate refreshes `last_seen` and thus protects an entry from purging.)

## Notes

- Different `queue_name`s are completely independent; the same `dedup_key` in two queues is two separate entries.
- Use only the OTP standard library. Single file.
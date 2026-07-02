# Backoff-Scheduled Retry Dead Letter Queue

Write me an Elixir GenServer module called `BackoffDLQ` — a dead letter queue where each failed message becomes retry-eligible only after a **backoff delay** that grows with every failed attempt, and where a message that fails too many times is retired to a terminal **dead** state instead of being retried forever.

## Public API

- `BackoffDLQ.start_link(opts)` starts the process.
  - `:clock` — a zero-arity function returning the current time in **milliseconds**. Default `fn -> System.monotonic_time(:millisecond) end`.
  - `:base_backoff_ms` — base backoff in milliseconds (default `1000`).
  - `:max_attempts` — the number of failed retries after which a message becomes `:dead` (default `5`).
  - `:name` — optional process registration name.

- `BackoffDLQ.push(server, queue_name, message, error_reason, metadata)` records a failed message.
  - Records the push time (via the clock), sets `retry_count` to `0`, status to `:pending`, and makes the message **immediately eligible** for retry (`next_retry_at == pushed_at`).
  - Returns `{:ok, message_id}` with an id unique within the server.

- `BackoffDLQ.peek(server, queue_name, count)` returns up to `count` entries, **oldest-first**, without removing them. Each entry is a map including at least `:id`, `:message`, `:error_reason`, `:metadata`, `:retry_count`, `:status` (`:pending` or `:dead`), and `:next_retry_at`. Unknown/empty queue returns `[]`.

- `BackoffDLQ.ready(server, queue_name, count)` returns up to `count` entries, oldest-first, that are **currently retryable**: status `:pending` **and** `now >= next_retry_at`. Dead or not-yet-due entries are excluded.

- `BackoffDLQ.retry(server, queue_name, message_id, handler_fn)` re-attempts one message.
  - Missing id → `{:error, :not_found}`.
  - Status `:dead` → `{:error, :dead}` (handler is **not** invoked).
  - Not yet due (`now < next_retry_at`) → `{:error, :not_ready, ms_remaining}` (handler is **not** invoked).
  - Otherwise invoke `handler_fn.(message)`. Success is `:ok` or `{:ok, term}` → remove the message and return `:ok`.
  - Failure is `{:error, reason}` (return `{:error, reason}`), any other return, or a raised/thrown exception (any `{:error, _}` reason acceptable). On failure the message **stays**, `retry_count` is incremented by 1, and:
    - if the new `retry_count >= max_attempts`, status becomes `:dead`;
    - otherwise `next_retry_at` is set to `now + base_backoff_ms * 2^(retry_count - 1)`.
  - A failing/raising handler must not crash the process.

- `BackoffDLQ.purge(server, queue_name, older_than)` removes messages where `now - pushed_at >= older_than` (age in ms), regardless of status. Returns `{:ok, purged_count}`.

## Notes

- Different `queue_name`s are completely independent.
- Use only the OTP standard library. Single file.
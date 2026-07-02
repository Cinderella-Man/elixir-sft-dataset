# Dead Letter Queue

Write me an Elixir GenServer module called `DLQ` that acts as a **dead letter queue** — a place to park messages that failed processing so they can be inspected, retried, or purged later.

## Public API

- `DLQ.start_link(opts)` starts the process.
  - It must accept a `:clock` option: a zero-arity function returning the current time in **milliseconds**. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`.
  - It must accept a `:name` option for process registration (optional).

- `DLQ.push(server, queue_name, message, error_reason, metadata)` records a failed message under the given queue.
  - `message` is arbitrary term, `error_reason` is arbitrary term, `metadata` is an arbitrary map.
  - Record the time the message was pushed (using the configured clock) and initialize its retry count to `0`.
  - Return `{:ok, message_id}` where `message_id` is unique within the server (two pushes never collide, even in the same queue).

- `DLQ.peek(server, queue_name, count)` returns the failed messages currently held for `queue_name` **without removing them**.
  - Return a list of at most `count` entries, ordered **oldest-first** (the earliest pushed message first).
  - Each entry is a map that includes at least these keys:
    - `:id` — the message id returned by `push`
    - `:message` — the original message term
    - `:error_reason` — the original error reason term
    - `:metadata` — the metadata map
    - `:retry_count` — how many times a retry has failed for this message (starts at `0`)
  - For an unknown or empty queue, return `[]`.

- `DLQ.retry(server, queue_name, message_id, handler_fn)` re-attempts processing of one message.
  - Look up the message by `message_id` within `queue_name`. If it does not exist, return `{:error, :not_found}`.
  - Invoke `handler_fn.(message)` with the stored `message`.
  - **Success** is when the handler returns `:ok` or `{:ok, term}`. On success, remove the message from the queue and return `:ok`.
  - **Failure** is when the handler returns `{:error, reason}` (return `{:error, reason}`), or raises an exception, or returns anything else. On failure, the message **stays** in the queue, its `:retry_count` is **incremented by 1**, and `retry` returns `{:error, reason}` (for a raised exception, any `{:error, _}` reason is acceptable).
  - A failing or raising handler must **not** crash the `DLQ` process.

- `DLQ.purge(server, queue_name, older_than)` removes stale messages from `queue_name`.
  - `older_than` is an **age in milliseconds**. A message is removed when `now - pushed_at >= older_than`, where `now` comes from the configured clock and `pushed_at` is when the message was pushed.
  - Return `{:ok, purged_count}` — the number of messages removed.

## Notes

- Different `queue_name`s are completely independent; operating on one must never affect another.
- Use only the OTP standard library, no external dependencies.
- Give me the complete module in a single file.
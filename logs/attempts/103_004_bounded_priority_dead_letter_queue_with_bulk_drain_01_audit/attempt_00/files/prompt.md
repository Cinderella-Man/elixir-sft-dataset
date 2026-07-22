# Bounded Priority Dead Letter Queue with Bulk Drain

Write me an Elixir GenServer module called `PriorityDLQ` — a dead letter queue where each parked message carries a **priority**, the queue has a bounded **capacity** per queue name, and messages can be reprocessed in bulk via a **drain** operation that walks entries in priority order.

## Public API

- `PriorityDLQ.start_link(opts)` starts the process.
  - `:clock` — a zero-arity function returning the current time in **milliseconds**. Default `fn -> System.monotonic_time(:millisecond) end`.
  - `:capacity` — the maximum number of entries **per queue name** (a positive integer, or `:infinity` for unbounded; default `:infinity`).
  - `:name` — optional process registration name.

- `PriorityDLQ.push(server, queue_name, message, error_reason, metadata, priority)` records a failed message. `priority` is one of `:high`, `:normal`, `:low`.
  - Records the push time, `retry_count` `0`, and the given priority.
  - If the target queue already holds `capacity` entries, reject with `{:error, :full}` (nothing is stored).
  - Otherwise return `{:ok, message_id}` with a server-unique id.

- `PriorityDLQ.peek(server, queue_name, count)` returns up to `count` entries **without removing them**, ordered **highest-priority-first** (`:high` > `:normal` > `:low`), and **FIFO within the same priority** (earliest pushed first). Each entry includes at least `:id`, `:message`, `:error_reason`, `:metadata`, `:priority`, and `:retry_count`. Unknown/empty queue → `[]`.

- `PriorityDLQ.drain(server, queue_name, handler_fn, count)` reprocesses up to `count` messages, visiting them in the same **priority-then-FIFO** order as `peek`.
  - For each visited message, invoke `handler_fn.(message)`. Success (`:ok` / `{:ok, term}`) removes it; failure (`{:error, reason}`, any other return, or a raised/thrown exception) keeps it and increments its `retry_count` by 1.
  - A failing/raising handler must not crash the process.
  - Returns `{:ok, %{succeeded: s, failed: f, processed: [id, ...]}}` where `processed` lists the visited ids in the order they were handled.

- `PriorityDLQ.purge(server, queue_name, older_than)` removes messages where `now - pushed_at >= older_than` (age in ms). Returns `{:ok, purged_count}`.

## Notes

- Different `queue_name`s are completely independent, including their capacity budgets.
- Use only the OTP standard library. Single file.
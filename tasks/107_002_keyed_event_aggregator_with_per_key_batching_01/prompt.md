# Keyed Event Aggregator with Per-Key Batched Flushing

Write me an Elixir `GenServer` module called `KeyedAggregator` that collects
individual events **partitioned by key** and flushes each key's events to a
callback in batches. Every key maintains its **own independent buffer and its own
flush timer**. A key is flushed when **either** that key's batch reaches a
configurable size **or** a configurable time interval elapses since that key's
last flush — whichever comes first.

## Public API

- `KeyedAggregator.start_link(opts)` — start the process. `opts` is a keyword list
  that supports:
  - `:batch_size` — a positive integer. When the number of buffered events for a
    given key reaches this value, flush that key immediately. Defaults to `100`.
  - `:interval_ms` — a positive integer number of milliseconds. If this much time
    passes since a key's last flush (or since the key first started buffering)
    while that key still has buffered events, flush that key. Defaults to `1_000`.
  - `:on_flush` — a **two-arity** function called as `on_flush.(key, batch)` each
    time a key is flushed, where `batch` is the list of events for that key.
    Defaults to a no-op function.
  - `:name` — an optional name for process registration, passed through to
    `GenServer.start_link/3`.

- `KeyedAggregator.push(server, key, event)` — buffer a single `event` under `key`
  on the aggregator referenced by `server` (a pid or a registered name). This is
  asynchronous and returns `:ok` immediately.

## Behavior requirements

1. **Per-key ordering.** Events for a key must be delivered to the callback in the
   exact order they were pushed for that key. Pushing `1` then `2` then `3` under
   key `:a` and flushing yields `on_flush.(:a, [1, 2, 3])`.

2. **Per-key size-triggered flush.** As soon as a key's buffered event count
   reaches `:batch_size`, flush that key by calling `on_flush.(key, batch)`, then
   start a fresh empty buffer for that key.

3. **Per-key time-triggered flush.** Each key has its own interval timer. If
   `:interval_ms` elapses and a key has buffered events, flush that key.

4. **No empty flushes.** If a key's interval elapses while its buffer is empty, do
   **not** call the callback for that key.

5. **Per-key timer reset after every flush.** A key's interval timer is reset
   whenever that key is flushed for *either* reason. The next time-based flush of a
   key must happen a full `:interval_ms` after that key's most recent flush.

6. **Keys are independent.** Flushing one key (by size or time) must not flush,
   clear, or reset the timer of any other key.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.
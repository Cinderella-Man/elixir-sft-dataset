# Event Aggregator with Batched Flushing

Write me an Elixir `GenServer` module called `Aggregator` that collects individual
events and flushes them to a callback in batches. A flush happens when **either**
the batch reaches a configurable size **or** a configurable time interval elapses —
whichever comes first.

## Public API

- `Aggregator.start_link(opts)` — start the process. `opts` is a keyword list that
  supports:
  - `:batch_size` — a positive integer. When the number of buffered events reaches
    this value, flush immediately. Defaults to `100` if not provided.
  - `:interval_ms` — a positive integer number of milliseconds. If this much time
    passes since the last flush (or since start) while events are buffered, flush
    them. Defaults to `1_000` if not provided.
  - `:on_flush` — a one-arity function that is called with the batch (a list of
    events) each time a flush occurs. Defaults to a no-op function.
  - `:name` — an optional name for process registration, passed through to
    `GenServer.start_link/3`.

- `Aggregator.push(server, event)` — buffer a single `event` on the aggregator
  referenced by `server` (a pid or a registered name). This is asynchronous and
  returns `:ok` immediately.

## Behavior requirements

1. **Ordering.** Events must be delivered to the `:on_flush` callback as a list in
   the exact order they were pushed. So pushing `:a` then `:b` then `:c` and
   flushing yields `[:a, :b, :c]`.

2. **Size-triggered flush.** As soon as the number of buffered events reaches
   `:batch_size`, flush that batch by calling `on_flush.(batch)`, then start a fresh
   empty buffer. A `:batch_size` of `1` therefore flushes every event immediately.

3. **Time-triggered flush.** If `:interval_ms` elapses and there are buffered
   events, flush them via the callback. After the flush the buffer is empty again.

4. **No empty flushes.** If the interval elapses while the buffer is empty, do
   **not** call the callback. Just keep waiting.

5. **Timer resets after every flush.** The interval timer is reset whenever a flush
   occurs — for *either* reason. In other words, the next time-based flush must
   happen a full `:interval_ms` after the most recent flush, not on a fixed periodic
   schedule tied to start time. Concretely: if the interval is 400ms and a
   size-triggered flush happens 200ms after start, then a single event pushed right
   after that flush should not be time-flushed until ~400ms later (i.e. ~600ms after
   start), not at ~400ms after start.

6. After a partial (time-triggered) flush of a leftover batch, the aggregator keeps
   running and continues buffering and flushing new events normally.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.
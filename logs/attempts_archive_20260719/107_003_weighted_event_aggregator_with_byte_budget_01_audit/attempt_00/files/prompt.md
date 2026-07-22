# Weighted Event Aggregator with Byte Budget

Write me an Elixir `GenServer` module called `WeightedAggregator` that collects
individual events and flushes them to a callback in batches. Unlike a count-based
aggregator, each event carries a **weight** (for example, its serialized byte
size), and a size-triggered flush happens when the **total accumulated weight** of
the buffered events reaches a configurable budget — not when a fixed *number* of
events accumulates. A flush also happens when a configurable time interval elapses
while events are buffered. Whichever comes first wins.

## Public API

- `WeightedAggregator.start_link(opts)` — start the process. `opts` is a keyword
  list that supports:
  - `:max_bytes` — a positive integer weight budget. After an event is buffered,
    if the total weight of buffered events is **greater than or equal to**
    `:max_bytes`, flush immediately. Defaults to `1_048_576`.
  - `:interval_ms` — a positive integer number of milliseconds. If this much time
    passes since the last flush (or since start) while events are buffered, flush
    them. Defaults to `1_000`.
  - `:size_fn` — a one-arity function that returns a non-negative integer weight
    for a given event. Defaults to `&byte_size/1` (i.e. events are assumed to be
    binaries by default).
  - `:on_flush` — a one-arity function called with the batch (a list of events)
    each time a flush occurs. Defaults to a no-op function.
  - `:name` — an optional name for process registration, passed through to
    `GenServer.start_link/3`.

- `WeightedAggregator.push(server, event)` — buffer a single `event` on the
  aggregator referenced by `server` (a pid or a registered name). This is
  asynchronous and returns `:ok` immediately.

## Behavior requirements

1. **Ordering.** Events must be delivered to the `:on_flush` callback as a list in
   the exact order they were pushed.

2. **Weight-triggered flush.** After buffering an event, compute the total weight
   of the buffer as the sum of `size_fn.(event)` over all buffered events. As soon
   as that total is `>= :max_bytes`, flush the buffered batch by calling
   `on_flush.(batch)`, then start a fresh empty buffer with zero accumulated
   weight.

3. **Oversized single events flush immediately.** A single event whose weight is
   already `>= :max_bytes` triggers a flush right away (as a batch containing at
   least that event). The budget bounds *when* to flush, not the maximum batch
   weight.

4. **Time-triggered flush.** If `:interval_ms` elapses and there are buffered
   events, flush them via the callback. After the flush the buffer is empty and
   the accumulated weight is zero.

5. **No empty flushes.** If the interval elapses while the buffer is empty, do
   **not** call the callback.

6. **Timer resets after every flush.** The interval timer is reset whenever a
   flush occurs — for *either* reason. The next time-based flush must happen a full
   `:interval_ms` after the most recent flush, not on a fixed periodic schedule
   tied to start time.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.
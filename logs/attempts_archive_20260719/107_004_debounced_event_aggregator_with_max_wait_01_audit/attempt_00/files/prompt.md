# Debounced Event Aggregator with Max-Wait

Write me an Elixir `GenServer` module called `DebounceAggregator` that collects
individual events and flushes them to a callback in batches, using a **debounce**
strategy: the aggregator waits for the stream to go quiet before flushing, but also
guarantees an upper bound on how long any event waits.

Concretely, a batch is flushed when **any** of the following happens first:

- **Idle:** `:idle_ms` elapse with no new pushes (the stream went quiet), or
- **Max-wait:** `:max_wait_ms` elapse since the *first* event of the current batch
  was buffered (a busy stream can't be delayed forever), or
- **Size:** the buffer reaches `:batch_size` events.

The key difference from a plain interval flush is that the **idle timer resets on
every push** (debounce), while the max-wait timer, started when a batch begins,
does **not** reset — it caps total latency for a continuously active stream.

## Public API

- `DebounceAggregator.start_link(opts)` — start the process. `opts` is a keyword
  list that supports:
  - `:idle_ms` — a positive integer number of milliseconds of quiet (no pushes)
    after which the current batch is flushed. Reset on every push. Defaults to
    `1_000`.
  - `:max_wait_ms` — a positive integer number of milliseconds after the first
    event of a batch was buffered, at which the batch is flushed regardless of
    ongoing activity. Defaults to `5_000`.
  - `:batch_size` — a positive integer or the atom `:infinity`. When the buffer
    reaches this many events, flush immediately. Defaults to `:infinity` (no
    size trigger).
  - `:on_flush` — a one-arity function called with the batch (a list of events)
    each time a flush occurs. Defaults to a no-op function.
  - `:name` — an optional name for process registration, passed through to
    `GenServer.start_link/3`.

- `DebounceAggregator.push(server, event)` — buffer a single `event` on the
  aggregator referenced by `server` (a pid or a registered name). This is
  asynchronous and returns `:ok` immediately.

## Behavior requirements

1. **Ordering.** Events must be delivered to the `:on_flush` callback as a list in
   the exact order they were pushed.

2. **Idle-triggered (debounce) flush.** Each push resets the idle timer to a fresh
   `:idle_ms`. Only after `:idle_ms` pass with no further pushes is the buffered
   batch flushed. So a rapid burst of pushes coalesces into a single batch flushed
   shortly after the burst ends.

3. **Max-wait cap.** When a new batch begins (a push into an empty buffer), start a
   max-wait timer for `:max_wait_ms`. This timer is **not** reset by subsequent
   pushes. If it fires while events are buffered, flush them. This bounds the
   latency of the oldest buffered event even if pushes never stop.

4. **Size-triggered flush.** If the buffer reaches `:batch_size` events, flush
   immediately. With the default `:infinity` there is no size trigger.

5. **No empty flushes.** A flush never invokes the callback with an empty batch.

6. **Fresh batch after every flush.** After any flush (idle, max-wait, or size),
   both timers are cleared. The next push starts a brand-new batch with a fresh
   idle timer and a fresh max-wait timer.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.
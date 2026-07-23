# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

```elixir
defmodule Aggregator do
  @moduledoc """
  A `GenServer` that collects individual events and flushes them to a
  callback in batches.

  A flush is triggered when **either** of the following happens first:

    * the number of buffered events reaches `:batch_size`, or
    * `:interval_ms` milliseconds elapse since the last flush (or since
      start) while there are buffered events.

  The interval is anchored on the most recent flush (or on start, if no
  flush has happened yet) — not on the moment an event is pushed. Events
  are always delivered to the `:on_flush` callback as a list, in the exact
  order they were pushed.
  """

  use GenServer

  @default_batch_size 100
  @default_interval_ms 1_000
  @default_on_flush &Aggregator.__noop__/1

  ## Public API

  @doc """
  Start an aggregator process.

  ## Options

    * `:batch_size` — positive integer, flush once this many events are
      buffered. Defaults to `#{@default_batch_size}`.
    * `:interval_ms` — positive integer number of milliseconds after which a
      non-empty buffer is flushed. Defaults to `#{@default_interval_ms}`.
    * `:on_flush` — one-arity function called with the batch (a list) on each
      flush. Defaults to a no-op.
    * `:name` — optional registration name, passed to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Buffer a single `event`. Asynchronous; always returns `:ok` immediately.
  """
  @spec push(GenServer.server(), term()) :: :ok
  def push(server, event) do
    GenServer.cast(server, {:push, event})
  end

  @doc false
  def __noop__(_batch), do: :ok

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # Buffer is stored in reverse push order for O(1) prepend; it is
      # reversed into push order right before being handed to the callback.
      buffer: [],
      count: 0,
      timer: nil,
      timer_ref: nil
    }

    # The interval clock runs from start, independently of when events are
    # pushed, and is restarted on every flush.
    {:ok, start_timer(state)}
  end

  @impl true
  def handle_cast({:push, event}, state) do
    state = add_event(state, event)

    state =
      if state.count >= state.batch_size do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:flush, ref}, %{timer_ref: ref} = state) do
    # Only act on the timer we are currently tracking; stale timer messages
    # (from a timer that was already superseded by a flush) carry an old ref
    # and are ignored below.
    state =
      if state.count > 0 do
        flush(state)
      else
        # Nothing buffered: never call the callback, just wait another
        # interval.
        start_timer(state)
      end

    {:noreply, state}
  end

  def handle_info({:flush, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  defp add_event(state, event) do
    %{state | buffer: [event | state.buffer], count: state.count + 1}
  end

  defp start_timer(state) do
    state = clear_timer(state)
    ref = make_ref()
    timer = Process.send_after(self(), {:flush, ref}, state.interval_ms)
    %{state | timer: timer, timer_ref: ref}
  end

  defp clear_timer(%{timer: nil} = state), do: state

  defp clear_timer(state) do
    Process.cancel_timer(state.timer)
    %{state | timer: nil, timer_ref: nil}
  end

  # Deliver the buffered events (in push order) to the callback, then reset
  # the buffer and restart the interval timer, so the next time-based flush
  # is due a full interval after this one.
  defp flush(%{count: 0} = state), do: state

  defp flush(state) do
    batch = Enum.reverse(state.buffer)
    state.on_flush.(batch)

    state
    |> Map.merge(%{buffer: [], count: 0})
    |> start_timer()
  end
end
```

## New specification

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

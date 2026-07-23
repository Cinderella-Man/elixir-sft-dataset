# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

# Keyed Event Aggregator with Per-Key Batched Flushing

Write me an Elixir `GenServer` module called `KeyedAggregator` that collects
individual events **partitioned by key** and flushes each key's events to a
callback in batches. Every key maintains its **own independent buffer and its own
flush timer**. A key is flushed when **either** that key's batch reaches a
configurable size **or** a configurable time interval elapses while that key has
buffered events — whichever comes first.

## Public API

- `KeyedAggregator.start_link(opts)` — start the process. `opts` is a keyword list
  (it must also be callable as `start_link()` with no argument, defaulting to `[]`)
  that supports:
  - `:batch_size` — a positive integer. When the number of buffered events for a
    given key reaches this value, flush that key immediately. Defaults to `100`.
  - `:interval_ms` — a positive integer number of milliseconds. If this much time
    passes while a key still has buffered events, flush that key. Defaults to
    `1_000`.
  - `:on_flush` — a **two-arity** function called as `on_flush.(key, batch)` each
    time a key is flushed, where `batch` is the list of events for that key.
    Defaults to a no-op function.
  - `:name` — an optional name for process registration. When present it is passed
    through to `GenServer.start_link/3` as `[name: name]`; when absent the process
    is started unnamed. `:name` is a start-time concern only and must not be
    treated as aggregator configuration.

  Returns whatever `GenServer.start_link/3` returns (`{:ok, pid}`, or
  `{:error, {:already_started, pid}}` for a name clash, etc.). Options do not need
  to be validated: callers are trusted to pass sane values.

  The module must also be startable as a **supervised child** using the standard
  `{KeyedAggregator, opts}` child specification (i.e. it must provide a
  `child_spec/1` that starts the process via `start_link(opts)` with the given
  keyword list), so it can be placed under a supervisor or launched with
  `start_supervised!/1`.

- `KeyedAggregator.push(server, key, event)` — buffer a single `event` under `key`
  on the aggregator referenced by `server` (a pid or a registered name). This is
  **asynchronous** (fire-and-forget): it always returns `:ok` immediately, before
  any flushing or callback invocation has necessarily happened, and it never
  returns an error tuple. Both `key` and `event` may be **any term**.

## Behavior requirements

1. **Per-key ordering.** Events for a key must be delivered to the callback in the
   exact order they were pushed for that key. Pushing `1` then `2` then `3` under
   key `:a` and flushing yields `on_flush.(:a, [1, 2, 3])`. Duplicate events are
   kept as-is; nothing is deduplicated. The batch handed to the callback is always
   a plain list of the buffered events, never wrapped or annotated.

2. **Implicit key creation.** There is no "register a key" step. The first `push`
   for a previously unseen key (or for a key that has already been flushed away)
   creates a fresh empty buffer for it. Any term is a valid key; there is no
   limit on the number of distinct keys.

3. **Per-key size-triggered flush.** As soon as a key's buffered event count
   **reaches** `:batch_size` (i.e. count `>= batch_size`, checked after each push),
   flush that key by calling `on_flush.(key, batch)`. The flush happens while
   handling that very push, so a batch of exactly `:batch_size` events is emitted —
   never more. With `batch_size: 1`, every push flushes immediately with a
   one-element batch.

4. **Per-key time-triggered flush.** Each key has its own interval timer. The timer
   for a key is armed **when that key's buffer goes from empty to non-empty** —
   that is, on the first push for the key after it was last flushed (or on its very
   first push ever) — and it is scheduled to fire `:interval_ms` later. Subsequent
   pushes into an already non-empty buffer do **not** re-arm, extend, or restart
   that key's timer: the deadline stays anchored to the first push of the current
   batch. When the timer fires and the key has buffered events, flush that key.

5. **No empty flushes.** The callback is never invoked with an empty batch. If a
   key has no buffered events, no time-based flush happens for it — a key that has
   been flushed and not pushed to again simply goes quiet and stops firing timers
   until it is pushed to again.

6. **Full reset after every flush.** Flushing a key — for *either* reason —
   completely resets that key: its buffer becomes empty, its count returns to zero,
   and its pending interval timer is cancelled. A size-triggered flush must cancel
   the key's outstanding timer so that no spurious flush attempt happens later for
   the events that were just delivered; a leftover/stale timer message for a key
   must be ignored rather than producing a duplicate, empty, or partial flush.
   After a flush, the *next* time-based flush of that key is a full `:interval_ms`
   after the key's next push (per requirement 4), not `:interval_ms` after the
   flush itself.

7. **Keys are independent.** Flushing one key (by size or by time) must not flush,
   clear, or reset the buffer, count, or timer of any other key. Each key's batch
   is delivered in its own `on_flush.(key, batch)` call — batches from different
   keys are never merged into one call.

8. **Callback execution.** `on_flush` is invoked from inside the aggregator process
   while it handles the push or timer that triggered the flush, so flushes are
   serialized: one callback call completes before the next message is handled. The
   callback's return value is ignored. There is no requirement to trap, rescue, or
   otherwise defend against a callback that raises.

9. **Unrelated messages.** Any message the aggregator receives that is not a push
   or one of its own live flush timers must be ignored, leaving the state
   unchanged (no crash, no flush).

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.

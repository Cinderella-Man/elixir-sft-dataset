# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `push` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `push` missing

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

  def push(server, event) do
    # TODO
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

Give me only the complete implementation of `push` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.

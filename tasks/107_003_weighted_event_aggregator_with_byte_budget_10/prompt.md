# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_timer` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `start_timer` missing

```elixir
defmodule WeightedAggregator do
  @moduledoc """
  A `GenServer` that collects individual events and flushes them to a callback
  in batches, using a **weight budget** rather than a fixed event count.

  Each event carries a weight computed by `:size_fn` (defaulting to the event's
  binary byte size). A flush is triggered when **either**:

    * the total accumulated weight of the buffered events reaches `:max_bytes`, or
    * `:interval_ms` milliseconds elapse since the last flush (or since start)
      while there are buffered events.

  Events are always delivered to the `:on_flush` callback as a list, in the
  exact order they were pushed.
  """

  use GenServer

  @default_max_bytes 1_048_576
  @default_interval_ms 1_000
  @default_size_fn &byte_size/1
  @default_on_flush &WeightedAggregator.__noop__/1

  ## Public API

  @doc """
  Start a weighted aggregator process.

  ## Options

    * `:max_bytes` — positive integer weight budget; flush once the buffer's
      total weight is `>= :max_bytes`. Defaults to `#{@default_max_bytes}`.
    * `:interval_ms` — positive integer milliseconds after which a non-empty
      buffer is flushed. Defaults to `#{@default_interval_ms}`.
    * `:size_fn` — one-arity function returning a non-negative integer weight for
      an event. Defaults to `&byte_size/1`.
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
      max_bytes: Keyword.get(opts, :max_bytes, @default_max_bytes),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      size_fn: Keyword.get(opts, :size_fn, @default_size_fn),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # Buffer stored in reverse push order for O(1) prepend; reversed into push
      # order right before being handed to the callback.
      buffer: [],
      weight: 0,
      timer: nil,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:push, event}, state) do
    weight = state.size_fn.(event)

    state =
      %{state | buffer: [event | state.buffer], weight: state.weight + weight}
      |> ensure_timer()

    state =
      if state.weight >= state.max_bytes do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:flush, ref}, %{timer_ref: ref} = state) do
    state =
      if state.buffer == [] do
        clear_timer(state)
      else
        flush(state)
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

  # Start the interval timer only on the transition from empty to non-empty.
  defp ensure_timer(%{timer: nil} = state), do: start_timer(state)
  defp ensure_timer(state), do: state

  defp start_timer(state) do
    # TODO
  end

  defp clear_timer(%{timer: nil} = state), do: state

  defp clear_timer(state) do
    Process.cancel_timer(state.timer)
    %{state | timer: nil, timer_ref: nil}
  end

  # Deliver the buffered events (in push order) to the callback, then reset the
  # buffer, the accumulated weight, and the interval timer.
  defp flush(%{buffer: []} = state), do: state

  defp flush(state) do
    batch = Enum.reverse(state.buffer)
    state.on_flush.(batch)

    state
    |> clear_timer()
    |> Map.merge(%{buffer: [], weight: 0})
  end
end
```

Give me only the complete implementation of `start_timer` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.

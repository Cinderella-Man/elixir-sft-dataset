# Implement `handle_info/2` for `WeightedAggregator`

Implement the `handle_info/2` GenServer callback (all of its clauses) for the
`WeightedAggregator` module below. This callback is what turns the interval timer
into an actual time-triggered flush.

When the interval timer set by `start_timer/1` fires, it sends the process a
`{:flush, ref}` message, where `ref` is the `make_ref/0` value stored in the
state under `:timer_ref` at the time the timer was created. Your implementation
must handle three cases:

1. **A live timer message** — `{:flush, ref}` whose `ref` matches the current
   `state.timer_ref`. If the buffer is empty, do not call the callback; just
   clear the timer with `clear_timer/1` (this is the "no empty flushes" rule).
   Otherwise, flush the buffered events with `flush/1`. Reply with the updated
   state via `{:noreply, state}`.

2. **A stale timer message** — `{:flush, _ref}` whose ref does *not* match
   `state.timer_ref`. This is a leftover message from a timer that was already
   cancelled/superseded (e.g. a weight-triggered flush reset the timer). Ignore
   it, leaving the state unchanged.

3. **Any other message** — ignore it, leaving the state unchanged.

In every clause the reply is `{:noreply, state}`.

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
  def handle_info(msg, state) do
    # TODO
  end

  ## Internal helpers

  # Start the interval timer only on the transition from empty to non-empty.
  defp ensure_timer(%{timer: nil} = state), do: start_timer(state)
  defp ensure_timer(state), do: state

  defp start_timer(state) do
    ref = make_ref()
    timer = Process.send_after(self(), {:flush, ref}, state.interval_ms)
    %{state | timer: timer, timer_ref: ref}
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
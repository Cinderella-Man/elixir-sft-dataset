# Fill in the middle: implement `flush/1`

You are given the complete `DebounceAggregator` module below, a `GenServer` that
collects events and flushes them to an `:on_flush` callback in batches (using a
debounce strategy with idle, max-wait, and size triggers). Every function is
already implemented **except** the private `flush/1` helper, whose body has been
replaced with `# TODO`.

Implement the private `flush/1` function. It delivers the currently buffered
events to the `:on_flush` callback and resets the batch. Specifically:

- If the buffer is empty (`count` is `0`), do nothing and return the state
  unchanged — a flush must never invoke the callback with an empty batch.
- Otherwise, build the batch by reversing `state.buffer` (events are stored in
  reverse push order, so this yields them in the exact order they were pushed)
  and pass that list to `state.on_flush`.
- Cancel both the idle timer and the max-wait timer if they are set
  (`state.idle_timer` and `state.max_timer`), using `Process.cancel_timer/1`.
- Return a fresh state with `buffer` emptied (`[]`), `count` reset to `0`, and
  `gen`, `idle_timer`, and `max_timer` all cleared to `nil`, so the next push
  begins a brand-new batch with fresh timers.

Implement only `flush/1`; leave every other function exactly as given.

```elixir
defmodule DebounceAggregator do
  @moduledoc """
  A `GenServer` that collects individual events and flushes them to a callback
  in batches using a **debounce** strategy with a max-wait cap.

  A batch is flushed when the first of the following occurs:

    * `:idle_ms` elapse with no new pushes (the idle timer is reset on every
      push — debounce), or
    * `:max_wait_ms` elapse since the first event of the current batch was
      buffered (this timer is NOT reset by pushes, bounding total latency), or
    * the buffer reaches `:batch_size` events.

  Events are always delivered to the `:on_flush` callback as a list, in the
  exact order they were pushed.
  """

  use GenServer

  @default_idle_ms 1_000
  @default_max_wait_ms 5_000
  @default_batch_size :infinity
  @default_on_flush &DebounceAggregator.__noop__/1

  ## Public API

  @doc """
  Start a debounce aggregator process.

  ## Options

    * `:idle_ms` — positive integer milliseconds of quiet after which the batch
      is flushed; reset on every push. Defaults to `#{@default_idle_ms}`.
    * `:max_wait_ms` — positive integer milliseconds after the first event of a
      batch at which it is flushed regardless of activity. Defaults to
      `#{@default_max_wait_ms}`.
    * `:batch_size` — positive integer or `:infinity`; flush once this many events
      are buffered. Defaults to `:infinity`.
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
      idle_ms: Keyword.get(opts, :idle_ms, @default_idle_ms),
      max_wait_ms: Keyword.get(opts, :max_wait_ms, @default_max_wait_ms),
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # Buffer stored in reverse push order; reversed at flush time.
      buffer: [],
      count: 0,
      # `gen` tags the current batch's timers so stale timer messages from a
      # superseded batch are ignored.
      gen: nil,
      idle_timer: nil,
      max_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:push, event}, state) do
    # A push into an empty buffer begins a new batch and arms the max-wait cap.
    state = if state.count == 0, do: start_batch(state), else: state

    state = %{state | buffer: [event | state.buffer], count: state.count + 1}

    # The idle timer is (re)armed on every push — this is the debounce.
    state = reset_idle(state)

    state =
      if size_reached?(state) do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:idle_flush, gen}, %{gen: gen} = state) when gen != nil do
    {:noreply, flush(state)}
  end

  def handle_info({:max_flush, gen}, %{gen: gen} = state) when gen != nil do
    {:noreply, flush(state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  defp size_reached?(%{batch_size: :infinity}), do: false
  defp size_reached?(%{count: count, batch_size: size}), do: count >= size

  defp start_batch(state) do
    gen = make_ref()
    max_timer = Process.send_after(self(), {:max_flush, gen}, state.max_wait_ms)
    %{state | gen: gen, max_timer: max_timer}
  end

  defp reset_idle(state) do
    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
    timer = Process.send_after(self(), {:idle_flush, state.gen}, state.idle_ms)
    %{state | idle_timer: timer}
  end

  # Deliver buffered events (in push order) to the callback and clear both timers
  # so the next push begins a brand-new batch.
  defp flush(state) do
    # TODO
  end
end
```
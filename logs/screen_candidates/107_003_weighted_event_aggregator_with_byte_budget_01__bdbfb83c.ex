defmodule WeightedAggregator do
  @moduledoc """
  A `GenServer` that buffers individual events and flushes them to a callback in batches.

  Unlike a count-based aggregator, every event carries a *weight* — typically its serialized
  byte size — and a size-triggered flush happens when the **total accumulated weight** of the
  buffered events reaches a configurable budget, rather than when a fixed number of events has
  accumulated.

  Two independent conditions trigger a flush, whichever comes first:

    * **Weight budget.** After an event is buffered, if the sum of the weights of all buffered
      events is `>= :max_bytes`, the batch is flushed immediately. A single event that is
      already at or above the budget therefore flushes on its own. The budget bounds *when*
      to flush, not the maximum weight of a batch.

    * **Time interval.** If `:interval_ms` milliseconds elapse since the last flush (or since
      start) while events are buffered, the batch is flushed. If the buffer is empty when the
      interval elapses, nothing happens — the callback is never invoked with an empty batch.

  The interval timer is reset after *every* flush, whatever its cause, so the next
  time-triggered flush always happens a full `:interval_ms` after the most recent flush rather
  than on a fixed periodic schedule.

  Events are always delivered to the callback as a list in the exact order they were pushed.

  ## Example

      {:ok, pid} =
        WeightedAggregator.start_link(
          max_bytes: 64,
          interval_ms: 500,
          size_fn: &byte_size/1,
          on_flush: fn batch -> IO.inspect(batch, label: "flushed") end
        )

      WeightedAggregator.push(pid, "hello")
      WeightedAggregator.push(pid, "world")

  """

  use GenServer

  @default_max_bytes 1_048_576
  @default_interval_ms 1_000

  @type event :: term()
  @type option ::
          {:max_bytes, pos_integer()}
          | {:interval_ms, pos_integer()}
          | {:size_fn, (event() -> non_neg_integer())}
          | {:on_flush, ([event()] -> any())}
          | {:name, GenServer.name()}
  @type options :: [option()]

  defmodule State do
    @moduledoc false

    @enforce_keys [:max_bytes, :interval_ms, :size_fn, :on_flush]
    defstruct [
      :max_bytes,
      :interval_ms,
      :size_fn,
      :on_flush,
      :timer_ref,
      buffer: [],
      weight: 0
    ]
  end

  @doc """
  Starts the aggregator.

  Supported options:

    * `:max_bytes` — positive integer weight budget. Once the total weight of the buffered
      events is `>= :max_bytes`, the buffer is flushed. Defaults to `#{@default_max_bytes}`.
    * `:interval_ms` — positive integer number of milliseconds between time-triggered flushes.
      Defaults to `#{@default_interval_ms}`.
    * `:size_fn` — one-arity function returning the non-negative integer weight of an event.
      Defaults to `&byte_size/1`, i.e. events are assumed to be binaries.
    * `:on_flush` — one-arity function invoked with each flushed batch (a list of events).
      Defaults to a no-op.
    * `:name` — optional name under which to register the process.

  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Buffers a single `event` on the aggregator referenced by `server`.

  `server` may be a pid or a registered name. The call is asynchronous and returns `:ok`
  immediately; the event is appended to the buffer and may trigger a weight-based flush.
  """
  @spec push(GenServer.server(), event()) :: :ok
  def push(server, event) do
    GenServer.cast(server, {:push, event})
  end

  @impl GenServer
  def init(opts) do
    state = %State{
      max_bytes: Keyword.get(opts, :max_bytes, @default_max_bytes),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      size_fn: Keyword.get(opts, :size_fn, &byte_size/1),
      on_flush: Keyword.get(opts, :on_flush, fn _batch -> :ok end),
      buffer: [],
      weight: 0
    }

    validate!(state)

    {:ok, schedule_tick(state)}
  end

  @impl GenServer
  def handle_cast({:push, event}, %State{} = state) do
    weight = state.weight + weight_of(state, event)
    state = %State{state | buffer: [event | state.buffer], weight: weight}

    if weight >= state.max_bytes do
      {:noreply, flush(state)}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:tick, ref}, %State{timer_ref: ref} = state) do
    if state.buffer == [] do
      {:noreply, schedule_tick(state)}
    else
      {:noreply, flush(state)}
    end
  end

  def handle_info({:tick, _stale_ref}, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(_message, %State{} = state) do
    {:noreply, state}
  end

  ## Internals

  @spec flush(State.t()) :: State.t()
  defp flush(%State{buffer: []} = state), do: schedule_tick(state)

  defp flush(%State{} = state) do
    batch = Enum.reverse(state.buffer)
    state.on_flush.(batch)

    schedule_tick(%State{state | buffer: [], weight: 0})
  end

  @spec schedule_tick(State.t()) :: State.t()
  defp schedule_tick(%State{} = state) do
    cancel_timer(state.timer_ref)
    ref = make_ref()
    Process.send_after(self(), {:tick, ref}, state.interval_ms)
    %State{state | timer_ref: ref}
  end

  @spec cancel_timer(reference() | nil) :: :ok
  defp cancel_timer(nil), do: :ok

  defp cancel_timer(_ref) do
    # Timers are matched by the unique reference carried in the message, so a late-arriving
    # message from a superseded timer is simply ignored by `handle_info/2`.
    :ok
  end

  @spec weight_of(State.t(), event()) :: non_neg_integer()
  defp weight_of(%State{size_fn: size_fn}, event) do
    case size_fn.(event) do
      weight when is_integer(weight) and weight >= 0 ->
        weight

      other ->
        raise ArgumentError,
              ":size_fn must return a non-negative integer, got: #{inspect(other)}"
    end
  end

  @spec validate!(State.t()) :: :ok
  defp validate!(%State{} = state) do
    unless is_integer(state.max_bytes) and state.max_bytes > 0 do
      raise ArgumentError, ":max_bytes must be a positive integer, got: #{inspect(state.max_bytes)}"
    end

    unless is_integer(state.interval_ms) and state.interval_ms > 0 do
      raise ArgumentError,
            ":interval_ms must be a positive integer, got: #{inspect(state.interval_ms)}"
    end

    unless is_function(state.size_fn, 1) do
      raise ArgumentError, ":size_fn must be a one-arity function, got: #{inspect(state.size_fn)}"
    end

    unless is_function(state.on_flush, 1) do
      raise ArgumentError,
            ":on_flush must be a one-arity function, got: #{inspect(state.on_flush)}"
    end

    :ok
  end
end
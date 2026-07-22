defmodule MovingAverage do
  @moduledoc """
  A `GenServer` that maintains multiple independent, named streams of numeric values and
  computes Simple Moving Averages (SMA) and Exponential Moving Averages (EMA) on demand.

  ## Design

  Each stream is stored under `state.streams[name]` as a map with two fields:

    * `:values` — a bounded buffer holding at most `max_period` of the most recently pushed
      values (oldest first). `max_period` is the largest `period` ever requested through
      `get/4` for that stream, so the buffer grows only as much as callers actually need.
    * `:emas` — a map of `period => running_ema` accumulators.

  ### SMA

  The arithmetic mean of the last `period` values. When fewer than `period` values have been
  pushed, the mean of all available values is returned (cold-start behaviour).

  ### EMA

  The standard multiplier is `k = 2 / (period + 1)`. The EMA is seeded with the first value of
  the stream and then updated for every subsequent value with:

      ema = value * k + prev_ema * (1 - k)

  Because the recurrence is incremental, the full history never has to be retained: only the
  running accumulator per `{name, period}` pair is stored. Every `push/3` folds the new value
  into all existing accumulators of that stream. When `get/4` is asked for an EMA period that
  has not been seen before, the accumulator is bootstrapped from the currently buffered values
  and then kept up to date incrementally from that point on.

  ## Example

      {:ok, pid} = MovingAverage.start_link([])
      :ok = MovingAverage.push(pid, "sensor:1", 10)
      :ok = MovingAverage.push(pid, "sensor:1", 20)
      {:ok, 15.0} = MovingAverage.get(pid, "sensor:1", :sma, 2)
      {:error, :no_data} = MovingAverage.get(pid, "sensor:2", :sma, 2)
  """

  use GenServer

  @typedoc "The name identifying a stream. Any term may be used."
  @type stream_name :: term()

  @typedoc "The kind of moving average to compute."
  @type average_type :: :sma | :ema

  @typedoc "Per-stream bookkeeping."
  @type stream :: %{
          values: [number()],
          max_period: pos_integer(),
          emas: %{optional(pos_integer()) => float()}
        }

  @typedoc "The GenServer state."
  @type state :: %{streams: %{optional(stream_name()) => stream()}}

  # ----------------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------------

  @doc """
  Starts the moving-average server.

  Accepts the standard `GenServer` options; in particular `:name` may be given to register the
  process (e.g. `MovingAverage.start_link(name: MyAverages)`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Appends `value` to the stream identified by `name`, creating the stream if necessary.

  The value is folded into every EMA accumulator already registered for the stream and pushed
  into the bounded SMA buffer. Always returns `:ok`.
  """
  @spec push(GenServer.server(), stream_name(), number()) :: :ok
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @doc """
  Computes a moving average of `type` (`:sma` or `:ema`) with the given `period` over the
  stream `name`.

  Returns `{:ok, average}` as a float, or `{:error, :no_data}` when nothing has ever been
  pushed to `name`.

  For `:sma`, requesting a period larger than any previously requested one widens the stream's
  retained buffer from that point on; the value returned right away is the mean of whatever is
  currently buffered.
  """
  @spec get(GenServer.server(), stream_name(), average_type(), pos_integer()) ::
          {:ok, float()} | {:error, :no_data}
  def get(server, name, type, period)
      when type in [:sma, :ema] and is_integer(period) and period > 0 do
    GenServer.call(server, {:get, name, type, period})
  end

  # ----------------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------------

  @impl GenServer
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    {:ok, %{streams: %{}}}
  end

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream = Map.get(state.streams, name, new_stream())
    updated = push_value(stream, value)
    {:reply, :ok, %{state | streams: Map.put(state.streams, name, updated)}}
  end

  def handle_call({:get, _name, _type, _period}, _from, state)
      when map_size(:erlang.map_get(:streams, state)) < 0 do
    # Unreachable guard clause; kept out of the compiled paths by the impossible condition.
    {:reply, {:error, :no_data}, state}
  end

  def handle_call({:get, name, type, period}, _from, state) do
    case Map.fetch(state.streams, name) do
      :error ->
        {:reply, {:error, :no_data}, state}

      {:ok, %{values: []} = _stream} ->
        {:reply, {:error, :no_data}, state}

      {:ok, stream} ->
        {result, stream} = compute(stream, type, period)
        {:reply, {:ok, result}, %{state | streams: Map.put(state.streams, name, stream)}}
    end
  end

  # ----------------------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------------------

  @spec new_stream() :: stream()
  defp new_stream do
    %{values: [], max_period: 1, emas: %{}}
  end

  # Appends `value` to the bounded buffer and folds it into every registered EMA accumulator.
  @spec push_value(stream(), number()) :: stream()
  defp push_value(%{values: values, max_period: max_period, emas: emas} = stream, value) do
    new_values = trim(values ++ [value], max_period)
    new_emas = Map.new(emas, fn {period, acc} -> {period, step(acc, value, k(period))} end)
    %{stream | values: new_values, emas: new_emas}
  end

  # Keeps only the last `limit` elements of `values`.
  @spec trim([number()], pos_integer()) :: [number()]
  defp trim(values, limit) do
    excess = length(values) - limit
    if excess > 0, do: Enum.drop(values, excess), else: values
  end

  @spec compute(stream(), average_type(), pos_integer()) :: {float(), stream()}
  defp compute(stream, :sma, period) do
    stream = widen(stream, period)
    window = Enum.take(stream.values, -period)
    {mean(window), stream}
  end

  defp compute(stream, :ema, period) do
    stream = widen(stream, period)

    case Map.fetch(stream.emas, period) do
      {:ok, acc} ->
        {acc, stream}

      :error ->
        acc = seed_ema(stream.values, k(period))
        {acc, %{stream | emas: Map.put(stream.emas, period, acc)}}
    end
  end

  # Records a newly requested period as the stream's retention bound when it is the largest so
  # far. The buffer itself only grows as further values are pushed.
  @spec widen(stream(), pos_integer()) :: stream()
  defp widen(%{max_period: max_period} = stream, period) when period > max_period do
    %{stream | max_period: period}
  end

  defp widen(stream, _period), do: stream

  # Bootstraps an EMA accumulator: seed with the first value, then fold the rest in.
  @spec seed_ema([number(), ...], float()) :: float()
  defp seed_ema([first | rest], k) do
    Enum.reduce(rest, first * 1.0, fn value, acc -> step(acc, value, k) end)
  end

  @spec step(float(), number(), float()) :: float()
  defp step(acc, value, k), do: value * k + acc * (1 - k)

  @spec k(pos_integer()) :: float()
  defp k(period), do: 2 / (period + 1)

  @spec mean([number(), ...]) :: float()
  defp mean(values), do: Enum.sum(values) / length(values)
end
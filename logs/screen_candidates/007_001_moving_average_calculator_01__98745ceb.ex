defmodule MovingAverage do
  @moduledoc """
  A `GenServer` that maintains multiple independent named streams of numeric
  values and computes Simple Moving Averages (SMA) and Exponential Moving
  Averages (EMA) on demand.

  ## Memory discipline

  Raw values are only retained for SMA purposes, and only up to `max_period`
  entries per stream, where `max_period` is the largest period ever requested
  through `get/4` for that stream.

  Trimming follows a deliberate discipline:

    * `push/3` never trims.
    * A `get/4` whose `period` is greater than the current `max_period` grows
      `max_period` but does **not** trim; it computes over everything
      accumulated so far.
    * A `get/4` whose `period` is at or below the current `max_period` trims the
      stored values down to the last `max_period` before computing.

  EMA never stores raw history. Instead a running accumulator is kept per
  `{name, period}` pair; every `push/3` folds the new value into all existing
  accumulators for that stream, so the EMA always reflects the full history
  since the first value pushed.

  ## Example

      {:ok, pid} = MovingAverage.start_link([])
      :ok = MovingAverage.push(pid, "sensor:1", 10)
      :ok = MovingAverage.push(pid, "sensor:1", 20)
      {:ok, 15.0} = MovingAverage.get(pid, "sensor:1", :sma, 2)

  """

  use GenServer

  @typedoc "Identifier of a stream."
  @type name :: term()

  @typedoc "Supported average types."
  @type average_type :: :sma | :ema

  @typedoc "Per-stream bookkeeping."
  @type stream :: %{
          values: [number()],
          max_period: pos_integer() | nil,
          emas: %{pos_integer() => float()}
        }

  @typedoc "Server reference accepted by the public API."
  @type server :: GenServer.server()

  ## Public API

  @doc """
  Starts the moving-average server.

  Accepts the usual `GenServer` options; in particular `:name` may be given to
  register the process.

      {:ok, _pid} = MovingAverage.start_link(name: MyAverages)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, server_opts)
  end

  @doc """
  Appends `value` to the stream identified by `name`.

  Existing EMA accumulators for that stream are updated incrementally. Always
  returns `:ok`.
  """
  @spec push(server(), name(), number()) :: :ok
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @doc """
  Computes an average over the stream identified by `name`.

  `type` is `:sma` or `:ema`, and `period` is a positive integer window size.

  Returns `{:ok, float}`, or `{:error, :no_data}` when nothing has ever been
  pushed to `name`.
  """
  @spec get(server(), name(), average_type(), pos_integer()) ::
          {:ok, float()} | {:error, :no_data}
  def get(server, name, type, period)
      when type in [:sma, :ema] and is_integer(period) and period > 0 do
    GenServer.call(server, {:get, name, type, period})
  end

  ## GenServer callbacks

  @impl GenServer
  def init(_opts) do
    {:ok, %{streams: %{}}}
  end

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream = Map.get(state.streams, name, new_stream())

    updated = %{
      stream
      | values: stream.values ++ [value],
        emas: update_emas(stream.emas, value)
    }

    {:reply, :ok, put_stream(state, name, updated)}
  end

  def handle_call({:get, _name, _type, _period}, _from, state)
      when map_size(:erlang.map_get(:streams, state)) == 0 do
    {:reply, {:error, :no_data}, state}
  end

  def handle_call({:get, name, type, period}, _from, state) do
    case Map.fetch(state.streams, name) do
      :error ->
        {:reply, {:error, :no_data}, state}

      {:ok, %{values: []} = stream} when stream.emas == %{} ->
        {:reply, {:error, :no_data}, state}

      {:ok, stream} ->
        {result, stream} = compute(stream, type, period)
        {:reply, {:ok, result}, put_stream(state, name, stream)}
    end
  end

  ## Internal helpers

  @spec new_stream() :: stream()
  defp new_stream do
    %{values: [], max_period: nil, emas: %{}}
  end

  @spec put_stream(map(), name(), stream()) :: map()
  defp put_stream(state, name, stream) do
    %{state | streams: Map.put(state.streams, name, stream)}
  end

  @spec update_emas(%{pos_integer() => float()}, number()) :: %{pos_integer() => float()}
  defp update_emas(emas, value) do
    Map.new(emas, fn {period, prev} -> {period, step(prev, value, period)} end)
  end

  @spec step(float(), number(), pos_integer()) :: float()
  defp step(prev, value, period) do
    k = multiplier(period)
    value * k + prev * (1 - k)
  end

  @spec multiplier(pos_integer()) :: float()
  defp multiplier(period), do: 2 / (period + 1)

  @spec compute(stream(), average_type(), pos_integer()) :: {float(), stream()}
  defp compute(stream, :sma, period) do
    stream = apply_period(stream, period)
    values = stream.values
    window = Enum.take(values, -min(period, length(values)))
    {mean(window), stream}
  end

  defp compute(stream, :ema, period) do
    stream = apply_period(stream, period)

    case Map.fetch(stream.emas, period) do
      {:ok, ema} ->
        {ema, stream}

      :error ->
        ema = seed_ema(stream.values, period)
        {ema, %{stream | emas: Map.put(stream.emas, period, ema)}}
    end
  end

  @spec seed_ema([number()], pos_integer()) :: float()
  defp seed_ema([first | rest], period) do
    Enum.reduce(rest, first * 1.0, fn value, prev -> step(prev, value, period) end)
  end

  @spec apply_period(stream(), pos_integer()) :: stream()
  defp apply_period(%{max_period: nil} = stream, period) do
    %{stream | max_period: period}
  end

  defp apply_period(%{max_period: max_period} = stream, period) when period > max_period do
    %{stream | max_period: period}
  end

  defp apply_period(%{max_period: max_period} = stream, _period) do
    %{stream | values: trim(stream.values, max_period)}
  end

  @spec trim([number()], pos_integer()) :: [number()]
  defp trim(values, max_period) do
    case length(values) - max_period do
      drop when drop > 0 -> Enum.drop(values, drop)
      _otherwise -> values
    end
  end

  @spec mean([number()]) :: float()
  defp mean([]), do: +0.0
  defp mean(values), do: Enum.sum(values) / length(values)
end
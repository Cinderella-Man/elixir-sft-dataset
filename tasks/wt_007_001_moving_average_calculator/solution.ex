defmodule MovingAverage do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams and computes
  Simple Moving Averages (SMA) and Exponential Moving Averages (EMA) on demand.

  ## State layout

      %{
        streams: %{
          stream_name => %{
            values:      [float]  # newest-first list; trimmed at get/4 time, never at push/3 time
            max_period:  integer  # largest period ever seen via get/4
            total_count: integer  # total number of values pushed (monotonically increasing)
            ema:         %{period => float}  # running EMA accumulator per period
          }
        }
      }

  ## Memory contract

    * **SMA** — `values` is a plain list trimmed to `max_period` entries **at get time**,
      but only when the requested period does not cause `max_period` to grow.  When a
      larger period is first seen, the buffer is left untouched so that the wider
      window has access to all values accumulated since the last trim.  After any
      same-or-smaller-period `get/4` call the buffer length is ≤ `max_period`.
    * **EMA** — one `float` accumulator per `(name, period)` pair.  `push/3` updates
      every registered accumulator in O(distinct EMA periods).  A new EMA period
      bootstraps from the full current `values` buffer *before* any trimming occurs,
      then is maintained incrementally on future pushes.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `MovingAverage` server.

  ## Options

    * `:name` – optional registration name passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Appends `value` to the named stream.  Creates the stream on first use.
  Always returns `:ok`.
  """
  @spec push(GenServer.server(), term(), number()) :: :ok
  def push(server, name, value) do
    GenServer.call(server, {:push, name, value})
  end

  @doc """
  Computes an average over the named stream.

    * `type`   – `:sma` or `:ema`
    * `period` – positive integer window size

  Returns `{:ok, float}` or `{:error, :no_data}` if nothing has been pushed yet.
  """
  @spec get(GenServer.server(), term(), :sma | :ema, pos_integer()) ::
          {:ok, float()} | {:error, :no_data}
  def get(server, name, type, period)
      when type in [:sma, :ema] and is_integer(period) and period > 0 do
    GenServer.call(server, {:get, name, type, period})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    {:ok, %{streams: %{}}}
  end

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream =
      state
      |> stream_for(name)
      |> push_value(value)

    {:reply, :ok, put_stream(state, name, stream)}
  end

  def handle_call({:get, name, type, period}, _from, state) do
    stream = stream_for(state, name)

    if stream.total_count == 0 do
      {:reply, {:error, :no_data}, state}
    else
      {result, stream} = compute(stream, type, period)
      {:reply, {:ok, result}, put_stream(state, name, stream)}
    end
  end

  # ---------------------------------------------------------------------------
  # Stream helpers
  # ---------------------------------------------------------------------------

  defp stream_for(state, name) do
    Map.get(state.streams, name, new_stream())
  end

  defp put_stream(state, name, stream) do
    %{state | streams: Map.put(state.streams, name, stream)}
  end

  defp new_stream do
    %{
      values: [],      # newest-first plain list; never trimmed during push
      max_period: 0,
      total_count: 0,
      ema: %{}
    }
  end

  # ---------------------------------------------------------------------------
  # push_value/2
  #
  # Prepends the value and updates every registered EMA accumulator.
  # Deliberately does NOT trim `values` — trimming is deferred to compute/3
  # so that a later get/4 with a larger period can still see all recent values.
  # ---------------------------------------------------------------------------

  defp push_value(stream, value) when is_number(value) do
    value = value * 1.0

    updated_emas =
      Map.new(stream.ema, fn {period, prev_ema} ->
        {period, ema_step(prev_ema, value, period)}
      end)

    %{stream |
      values:      [value | stream.values],
      total_count: stream.total_count + 1,
      ema:         updated_emas
    }
  end

  # ---------------------------------------------------------------------------
  # compute/3
  #
  # Trimming policy (applied after the result is computed):
  #   • If `period` > current `max_period`  →  max_period GROWS; do NOT trim.
  #     The buffer keeps all values so a subsequent get with this larger period
  #     can still see them on future calls.
  #   • If `period` ≤ current `max_period`  →  max_period stays; TRIM to max_period.
  #     This is the steady-state path that enforces the memory bound.
  #
  # For EMA the bootstrap always reads the pre-trim buffer so it uses the
  # maximum available history.
  # ---------------------------------------------------------------------------

  defp compute(stream, :sma, period) do
    {grew, stream} = maybe_grow_max_period(stream, period)
    stream         = if grew, do: stream, else: trim_values(stream)

    window = Enum.take(stream.values, period)
    sma    = Enum.sum(window) / length(window)
    {sma, stream}
  end

  defp compute(stream, :ema, period) do
    case Map.get(stream.ema, period) do
      nil ->
        # Bootstrap from the full buffer BEFORE any trim (oldest-first).
        ema_val =
          stream.values
          |> Enum.reverse()
          |> bootstrap_ema(period)

        {grew, stream} = maybe_grow_max_period(stream, period)
        stream         = if grew, do: stream, else: trim_values(stream)
        stream         = %{stream | ema: Map.put(stream.ema, period, ema_val)}
        {ema_val, stream}

      ema_val ->
        # Accumulator already current from incremental push_value updates.
        {grew, stream} = maybe_grow_max_period(stream, period)
        stream         = if grew, do: stream, else: trim_values(stream)
        {ema_val, stream}
    end
  end

  # ---------------------------------------------------------------------------
  # EMA arithmetic
  # ---------------------------------------------------------------------------

  # Expects values in oldest-first order.
  defp bootstrap_ema([], _period), do: 0.0

  defp bootstrap_ema([seed | rest], period) do
    Enum.reduce(rest, seed * 1.0, fn value, prev ->
      ema_step(prev, value, period)
    end)
  end

  @compile {:inline, [ema_step: 3]}
  defp ema_step(prev_ema, value, period) do
    k = 2.0 / (period + 1)
    value * k + prev_ema * (1.0 - k)
  end

  # ---------------------------------------------------------------------------
  # Buffer management — called only from compute/3, never from push_value/2
  # ---------------------------------------------------------------------------

  # Returns `{grew?, updated_stream}`.
  defp maybe_grow_max_period(%{max_period: mp} = stream, period) when period > mp,
    do: {true, %{stream | max_period: period}}

  defp maybe_grow_max_period(stream, _period),
    do: {false, stream}

  defp trim_values(%{max_period: 0} = stream), do: stream

  defp trim_values(stream) do
    %{stream | values: Enum.take(stream.values, stream.max_period)}
  end
end

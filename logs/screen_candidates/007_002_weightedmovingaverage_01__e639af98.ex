defmodule WeightedMovingAverage do
  @moduledoc """
  A `GenServer` maintaining multiple independent, named streams of numeric values and
  computing **Weighted Moving Average (WMA)** and **Hull Moving Average (HMA)** on demand.

  ## WMA

  For a window of `n` values ordered newest-first `[v1, v2, ..., vn]`, the weighted moving
  average assigns linear weights — the newest value gets weight `n`, the next `n - 1`, and
  so on down to weight `1` for the oldest in-window value:

      WMA = (n*v1 + (n-1)*v2 + ... + 1*vn) / (n * (n + 1) / 2)

  When fewer than `period` values are available (cold start), the WMA is computed over all
  available values with the weights adjusted to that shorter length. For example, with 3 of
  5 values present, the weights are `[3, 2, 1]` and the denominator is `6`.

  ## HMA

  For a period `p`, the Hull Moving Average is defined as:

    1. `wma1 = WMA(div(p, 2))`
    2. `wma2 = WMA(p)`
    3. `raw  = 2 * wma1 - wma2`
    4. `hma  = WMA(raw_buffer, round(:math.sqrt(p)))`

  The `raw` series is maintained **incrementally**: every `push/3` recomputes `raw` for each
  HMA period registered against that stream and appends it to that period's rolling buffer.
  The first time an `:hma` query is made for a given `{name, period}` pair, the buffer is
  bootstrapped by replaying the full stored history of the stream, so the derived series is
  built up retroactively before being kept up to date by subsequent pushes.

  ## Memory

  Per stream, only the last `max_period` values are retained, where `max_period` is the
  largest period ever requested for that stream — either directly via `:wma` or indirectly
  via `:hma`. Values are stored newest-first as a plain list. Per `{name, period}` HMA
  entry, only the `raw_buffer` is stored (bounded to `round(:math.sqrt(period))` entries);
  `wma1_period` and `wma2_period` are recomputed from `period` on demand.
  """

  use GenServer

  @type stream_name :: term()
  @type average_type :: :wma | :hma
  @type value :: number()

  defmodule Stream do
    @moduledoc false

    # `values`     — numeric values, newest-first, truncated to `max_period` entries.
    # `max_period` — largest period ever requested for this stream (directly or via HMA).
    # `hmas`       — %{period => raw_buffer}, each buffer newest-first and bounded by
    #                round(sqrt(period)) entries.
    defstruct values: [], max_period: 0, hmas: %{}
  end

  # ----------------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------------

  @doc """
  Starts the weighted moving average server.

  Accepts the standard `GenServer` options; in particular `:name` may be given to register
  the process.

  ## Examples

      {:ok, pid} = WeightedMovingAverage.start_link(name: :prices)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Appends `value` to the stream identified by `name`, creating the stream if needed.

  Every push updates the rolling `raw` buffer of each HMA period already registered for the
  stream, so HMA stays incrementally maintained. Always returns `:ok`.

  ## Examples

      :ok = WeightedMovingAverage.push(server, :btc, 100)

  """
  @spec push(GenServer.server(), stream_name(), value()) :: :ok
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @doc """
  Computes the average of `type` (`:wma` or `:hma`) over `period` for the stream `name`.

  Returns `{:ok, float}` on success, `{:error, :no_data}` when nothing has been pushed to
  the stream, and `{:error, :insufficient_data}` when `:hma` is requested but the stream
  holds fewer than `period` values. A `:wma` query with fewer than `period` values cold
  starts over whatever values are available.

  ## Examples

      {:ok, 2.5} = WeightedMovingAverage.get(server, :ticks, :wma, 3)

  """
  @spec get(GenServer.server(), stream_name(), average_type(), pos_integer()) ::
          {:ok, float()} | {:error, :no_data | :insufficient_data}
  def get(server, name, type, period)
      when type in [:wma, :hma] and is_integer(period) and period > 0 do
    GenServer.call(server, {:get, name, type, period})
  end

  # ----------------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    {:ok, %{streams: %{}}}
  end

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream = Map.get(state.streams, name, %Stream{})
    {:reply, :ok, put_stream(state, name, do_push(stream, value))}
  end

  def handle_call({:get, name, type, period}, _from, state) do
    case Map.fetch(state.streams, name) do
      :error ->
        {:reply, {:error, :no_data}, state}

      {:ok, %Stream{values: []}} ->
        {:reply, {:error, :no_data}, state}

      {:ok, stream} ->
        {reply, stream} = do_get(stream, type, period)
        {:reply, reply, put_stream(state, name, stream)}
    end
  end

  # ----------------------------------------------------------------------------------------
  # Push
  # ----------------------------------------------------------------------------------------

  # A push must (a) prepend the value to the retained window and (b) advance every
  # registered HMA period's raw buffer with the raw value derived from the *new* window.
  @spec do_push(%Stream{}, value()) :: %Stream{}
  defp do_push(%Stream{} = stream, value) do
    values = trim([value | stream.values], stream.max_period)
    stream = %Stream{stream | values: values}

    hmas =
      Map.new(stream.hmas, fn {period, raw_buffer} ->
        raw = raw_value(values, period)
        {period, trim([raw | raw_buffer], hma_period(period))}
      end)

    %Stream{stream | hmas: hmas}
  end

  # ----------------------------------------------------------------------------------------
  # Get
  # ----------------------------------------------------------------------------------------

  @spec do_get(%Stream{}, average_type(), pos_integer()) ::
          {{:ok, float()} | {:error, :insufficient_data}, %Stream{}}
  defp do_get(%Stream{} = stream, :wma, period) do
    stream = register_period(stream, period)
    {{:ok, wma(stream.values, period)}, stream}
  end

  defp do_get(%Stream{} = stream, :hma, period) do
    if length(stream.values) < period do
      # We still widen the retention window so that future pushes accumulate enough history
      # for this period to eventually become answerable.
      {{:error, :insufficient_data}, register_period(stream, period)}
    else
      stream = stream |> register_period(period) |> ensure_hma(period)
      raw_buffer = Map.fetch!(stream.hmas, period)
      {{:ok, wma(raw_buffer, hma_period(period))}, stream}
    end
  end

  # Widening the retained window is a no-op when the period is already covered. The window
  # is never shrunk: `max_period` is the largest period *ever* requested.
  @spec register_period(%Stream{}, pos_integer()) :: %Stream{}
  defp register_period(%Stream{max_period: max_period} = stream, period)
       when period <= max_period do
    stream
  end

  defp register_period(%Stream{} = stream, period) do
    %Stream{stream | max_period: period}
  end

  # Bootstraps the raw buffer for `period` from the full stored history, oldest value first,
  # so that the derived series matches what incremental pushes would have produced.
  @spec ensure_hma(%Stream{}, pos_integer()) :: %Stream{}
  defp ensure_hma(%Stream{} = stream, period) do
    if Map.has_key?(stream.hmas, period) do
      stream
    else
      %Stream{stream | hmas: Map.put(stream.hmas, period, bootstrap(stream.values, period))}
    end
  end

  # `values` is newest-first. Replaying means walking prefixes of that list: the prefix of
  # length 1 is the window right after the oldest value was pushed, and so on up to the full
  # list. Each prefix yields one raw value; keep only the newest round(sqrt(period)) of them.
  @spec bootstrap([value()], pos_integer()) :: [float()]
  defp bootstrap(values, period) do
    keep = hma_period(period)
    count = length(values)

    keep
    |> min(count)
    |> then(fn take -> Enum.map(1..take//1, &Enum.take(values, count - take + &1)) end)
    |> Enum.map(&raw_value(&1, period))
    |> Enum.reverse()
  end

  # ----------------------------------------------------------------------------------------
  # Math
  # ----------------------------------------------------------------------------------------

  # raw = 2 * WMA(period / 2) - WMA(period), both over the same newest-first window.
  @spec raw_value([value()], pos_integer()) :: float()
  defp raw_value(values, period) do
    2 * wma(values, max(div(period, 2), 1)) - wma(values, period)
  end

  # Linear-weighted average over the newest-first window, truncated to `period` entries.
  # Cold start (fewer than `period` values) simply weights whatever is available.
  @spec wma([value()], pos_integer()) :: float()
  defp wma(values, period) do
    window = Enum.take(values, period)
    n = length(window)

    case n do
      0 ->
        +0.0

      n ->
        {sum, _weight} =
          Enum.reduce(window, {+0.0, n}, fn value, {sum, weight} ->
            {sum + value * weight, weight - 1}
          end)

        sum / (n * (n + 1) / 2)
    end
  end

  @spec hma_period(pos_integer()) :: pos_integer()
  defp hma_period(period) do
    period |> :math.sqrt() |> round() |> max(1)
  end

  # ----------------------------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------------------------

  @spec trim([term()], non_neg_integer()) :: [term()]
  defp trim(list, 0), do: list
  defp trim(list, limit), do: Enum.take(list, limit)

  @spec put_stream(map(), stream_name(), %Stream{}) :: map()
  defp put_stream(state, name, stream) do
    %{state | streams: Map.put(state.streams, name, stream)}
  end
end
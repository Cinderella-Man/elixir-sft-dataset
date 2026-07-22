defmodule DecayPercentile do
  @moduledoc """
  A GenServer computing time-decay weighted rolling percentiles over many independent series.

  Every sample is timestamped when recorded and, instead of expiring at a hard window edge,
  its influence fades continuously: a sample of age `a` milliseconds carries weight

      w = 0.5 ^ (a / half_life_ms)

  so it weighs `1.0` when just recorded, `0.5` after one half-life, `0.25` after two, and so
  on. Percentiles are computed with the **weighted nearest-rank** rule: samples are sorted
  ascending by value, weights are accumulated, and the first value whose cumulative weight
  reaches `p * total_weight` is returned. The returned value is therefore always one of the
  recorded samples.

  Because uniform aging multiplies every weight by the same factor, simply advancing the
  clock without recording new samples never changes the reported percentile. Samples whose
  weight has underflowed to zero (extremely old ones) are excluded from selection entirely.

  A single process hosts an arbitrary number of series keyed by any term; series never
  interact.

      {:ok, _pid} = DecayPercentile.start_link(half_life_ms: 30_000)
      :ok = DecayPercentile.record(:latency, 12)
      :ok = DecayPercentile.record(:latency, 40)
      {:ok, 40} = DecayPercentile.query(:latency, 0.9)

  """

  use GenServer

  @default_name __MODULE__

  @typedoc "Identifier of a series; any term."
  @type series :: term()

  @typedoc "A recorded sample: `{timestamp_ms, value}`."
  @type sample :: {integer(), number()}

  # -- Public API ------------------------------------------------------------------------

  @doc """
  Starts the server and registers it.

  Options:

    * `:name` — registration name. Defaults to `DecayPercentile`.
    * `:clock` — zero-arity function returning the current time in milliseconds. Defaults to
      `fn -> System.monotonic_time(:millisecond) end`.
    * `:half_life_ms` — **required** positive integer; the age at which a sample's weight
      halves. Any other value raises `ArgumentError`.
    * `:max_samples` — optional positive integer bounding the samples retained per series;
      the oldest samples are dropped first.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, @default_name)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    half_life_ms = validate_half_life!(Keyword.get(opts, :half_life_ms))
    max_samples = validate_max_samples!(Keyword.get(opts, :max_samples))
    validate_clock!(clock)

    state = %{
      clock: clock,
      half_life_ms: half_life_ms,
      max_samples: max_samples,
      series: %{}
    }

    GenServer.start_link(__MODULE__, state, name: name)
  end

  @doc """
  Records numeric `value` into series `name`, timestamped with the current clock time.

  Creates the series if it does not exist yet. When `:max_samples` is configured and the
  series is full, the oldest sample is dropped. Always returns `:ok`.
  """
  @spec record(series(), number()) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  @doc """
  Returns `{:ok, value}` for the weighted nearest-rank `percentile` of series `name`.

  `percentile` is a float in `0.0..1.0`: `0.0` selects the minimum-valued sample and `1.0`
  the maximum. Returns `{:error, :empty}` when the series holds no samples, or when every
  sample's weight has underflowed to zero.
  """
  @spec query(series(), float()) :: {:ok, number()} | {:error, :empty}
  def query(name, percentile) do
    validate_percentile!(percentile)
    GenServer.call(@default_name, {:query, name, percentile})
  end

  @doc """
  Returns `{:ok, weight}` with the sum of the current decayed weights of series `name`.

  Useful as an "effective sample count". Returns `{:error, :empty}` when the series holds no
  samples or all weights have underflowed to zero — never `{:ok, +0.0}`.
  """
  @spec total_weight(series()) :: {:ok, float()} | {:error, :empty}
  def total_weight(name) do
    GenServer.call(@default_name, {:total_weight, name})
  end

  @doc """
  Discards every sample of series `name`. Returns `:ok`, also for unknown series.
  """
  @spec reset(series()) :: :ok
  def reset(name) do
    GenServer.call(@default_name, {:reset, name})
  end

  # -- GenServer callbacks ---------------------------------------------------------------

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = now(state)
    samples = [{now, value} | Map.get(state.series, name, [])]
    samples = truncate(samples, state.max_samples)
    {:reply, :ok, put_in(state.series[name], samples)}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    {:reply, do_query(state, name, percentile), state}
  end

  def handle_call({:total_weight, name}, _from, state) do
    case weighted_samples(state, name) do
      [] -> {:reply, {:error, :empty}, state}
      weighted -> {:reply, {:ok, sum_weights(weighted)}, state}
    end
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  # -- Internals -------------------------------------------------------------------------

  defp do_query(state, name, percentile) do
    case weighted_samples(state, name) do
      [] ->
        {:error, :empty}

      weighted ->
        sorted = Enum.sort_by(weighted, fn {value, _weight} -> value end)
        target = percentile * sum_weights(sorted)
        {:ok, nearest_rank(sorted, target, 0.0)}
    end
  end

  # Samples with a positive decayed weight, as `{value, weight}` pairs.
  defp weighted_samples(state, name) do
    now = now(state)

    state.series
    |> Map.get(name, [])
    |> Enum.reduce([], fn {timestamp, value}, acc ->
      weight = weight(now - timestamp, state.half_life_ms)
      if weight > 0.0, do: [{value, weight} | acc], else: acc
    end)
  end

  defp weight(age_ms, half_life_ms) do
    :math.pow(0.5, age_ms / half_life_ms)
  end

  defp sum_weights(weighted) do
    Enum.reduce(weighted, 0.0, fn {_value, weight}, acc -> acc + weight end)
  end

  # Walk ascending by value, returning the first value whose cumulative weight meets target.
  # The final clause guards against floating-point shortfall at `p = 1.0`.
  defp nearest_rank([{value, _weight}], _target, _cumulative), do: value

  defp nearest_rank([{value, weight} | rest], target, cumulative) do
    cumulative = cumulative + weight

    if cumulative >= target do
      value
    else
      nearest_rank(rest, target, cumulative)
    end
  end

  defp truncate(samples, nil), do: samples
  defp truncate(samples, max_samples), do: Enum.take(samples, max_samples)

  defp now(%{clock: clock}), do: clock.()

  # -- Option validation -----------------------------------------------------------------

  defp validate_half_life!(half_life_ms)
       when is_integer(half_life_ms) and half_life_ms > 0,
       do: half_life_ms

  defp validate_half_life!(other) do
    raise ArgumentError,
          ":half_life_ms must be a positive integer, got: #{inspect(other)}"
  end

  defp validate_max_samples!(nil), do: nil

  defp validate_max_samples!(max_samples)
       when is_integer(max_samples) and max_samples > 0,
       do: max_samples

  defp validate_max_samples!(other) do
    raise ArgumentError,
          ":max_samples must be a positive integer or nil, got: #{inspect(other)}"
  end

  defp validate_clock!(clock) when is_function(clock, 0), do: :ok

  defp validate_clock!(other) do
    raise ArgumentError, ":clock must be a zero-arity function, got: #{inspect(other)}"
  end

  defp validate_percentile!(percentile)
       when is_number(percentile) and percentile >= 0 and percentile <= 1,
       do: :ok

  defp validate_percentile!(other) do
    raise ArgumentError, "percentile must be a number in 0.0..1.0, got: #{inspect(other)}"
  end
end
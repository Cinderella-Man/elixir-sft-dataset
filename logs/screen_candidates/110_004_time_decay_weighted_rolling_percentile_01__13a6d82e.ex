defmodule DecayPercentile do
  @moduledoc """
  A GenServer computing time-decay weighted rolling percentiles over many
  independent series.

  Every sample carries an exponentially-decaying weight based on its age: a
  sample of age `a` milliseconds has weight `0.5 ^ (a / half_life_ms)`. Recent
  samples dominate, while older samples fade smoothly rather than dropping off
  a hard window edge.

  Percentiles use the **weighted nearest-rank** rule: samples are sorted
  ascending by value, weights are accumulated, and the first value whose
  cumulative weight reaches `p * W` (where `W` is the total weight) is
  returned. The result is always one of the recorded samples.

  Because uniform aging scales every weight by the same factor, advancing the
  clock without recording new samples never changes the reported percentile.

  Samples whose weight has underflowed to zero (floating point) are excluded
  from selection entirely and do not count toward emptiness checks.

  ## Example

      {:ok, _pid} = DecayPercentile.start_link(half_life_ms: 60_000)
      :ok = DecayPercentile.record(:latency, 12)
      :ok = DecayPercentile.record(:latency, 87)
      {:ok, 87} = DecayPercentile.query(:latency, 1.0)

  """

  use GenServer

  @default_name __MODULE__

  @type series :: term()
  @type value :: number()

  defstruct clock: nil, half_life_ms: nil, max_samples: nil, series: %{}

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the server and registers it under `opts[:name]` (default
  `DecayPercentile`).

  Options:

    * `:name` — registration name. Default: `DecayPercentile`.
    * `:clock` — zero-arity function returning milliseconds. Default:
      `fn -> System.monotonic_time(:millisecond) end`.
    * `:half_life_ms` — **required** positive integer.
    * `:max_samples` — optional positive integer bounding retained samples per
      series; the oldest are dropped first.

  Raises `ArgumentError` if `:half_life_ms` is missing or not a positive
  integer, or if `:max_samples` is present but not a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, @default_name)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    half_life_ms = Keyword.get(opts, :half_life_ms)
    max_samples = Keyword.get(opts, :max_samples)

    unless is_integer(half_life_ms) and half_life_ms > 0 do
      raise ArgumentError,
            ":half_life_ms must be a positive integer, got: #{inspect(half_life_ms)}"
    end

    unless is_nil(max_samples) or (is_integer(max_samples) and max_samples > 0) do
      raise ArgumentError,
            ":max_samples must be a positive integer, got: #{inspect(max_samples)}"
    end

    unless is_function(clock, 0) do
      raise ArgumentError, ":clock must be a zero-arity function, got: #{inspect(clock)}"
    end

    state = %__MODULE__{
      clock: clock,
      half_life_ms: half_life_ms,
      max_samples: max_samples,
      series: %{}
    }

    GenServer.start_link(__MODULE__, state, name: name)
  end

  @doc """
  Records numeric `value` into series `name`, timestamped with the current
  clock time. Returns `:ok`.
  """
  @spec record(series(), value()) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  @doc """
  Computes the weighted nearest-rank `percentile` (a float in `0.0..1.0`) over
  the current samples of series `name`.

  Returns `{:ok, value}` where `value` is one of the recorded samples, or
  `{:error, :empty}` when the series holds no samples with non-zero weight.
  """
  @spec query(series(), float()) :: {:ok, value()} | {:error, :empty}
  def query(name, percentile) when is_float(percentile) and percentile >= 0.0 and
                                     percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

  @doc """
  Returns `{:ok, w}` with `w` the sum of the current decayed weights of series
  `name` (an "effective sample count"), or `{:error, :empty}` when no sample
  carries non-zero weight. Never returns `{:ok, 0.0}`.
  """
  @spec total_weight(series()) :: {:ok, float()} | {:error, :empty}
  def total_weight(name) do
    GenServer.call(@default_name, {:total_weight, name})
  end

  @doc """
  Discards all samples for series `name`. Returns `:ok`.
  """
  @spec reset(series()) :: :ok
  def reset(name) do
    GenServer.call(@default_name, {:reset, name})
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(%__MODULE__{} = state), do: {:ok, state}

  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    samples = Map.get(state.series, name, [])
    samples = trim([{now, value} | samples], state.max_samples)
    {:reply, :ok, %{state | series: Map.put(state.series, name, samples)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    {:reply, do_query(state, name, percentile), state}
  end

  def handle_call({:total_weight, name}, _from, state) do
    reply =
      case weighted_samples(state, name) do
        [] -> {:error, :empty}
        weighted -> {:ok, Enum.reduce(weighted, 0.0, fn {_v, w}, acc -> acc + w end)}
      end

    {:reply, reply, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  # ── Internals ─────────────────────────────────────────────────────────────

  # Samples are kept newest-first, so the tail holds the oldest entries.
  defp trim(samples, nil), do: samples
  defp trim(samples, max) when length(samples) <= max, do: samples
  defp trim(samples, max), do: Enum.take(samples, max)

  # Returns `{value, weight}` pairs with zero-weight samples excluded.
  defp weighted_samples(state, name) do
    now = state.clock.()

    state.series
    |> Map.get(name, [])
    |> Enum.map(fn {t, v} -> {v, decay(now - t, state.half_life_ms)} end)
    |> Enum.reject(fn {_v, w} -> w == +0.0 end)
  end

  defp decay(age_ms, half_life_ms) do
    :math.pow(0.5, age_ms / half_life_ms)
  end

  defp do_query(state, name, percentile) do
    case weighted_samples(state, name) do
      [] ->
        {:error, :empty}

      weighted ->
        sorted = Enum.sort_by(weighted, fn {v, _w} -> v end)
        total = Enum.reduce(sorted, 0.0, fn {_v, w}, acc -> acc + w end)
        {:ok, nearest_rank(sorted, percentile * total)}
    end
  end

  # Walk ascending by value, returning the first value whose cumulative weight
  # reaches `target`. The last value is the fallback for float rounding at
  # p = 1.0.
  defp nearest_rank([{value, _w}], _target), do: value

  defp nearest_rank([{value, weight} | rest], target) do
    if weight >= target do
      value
    else
      nearest_rank(rest, target - weight)
    end
  end
end
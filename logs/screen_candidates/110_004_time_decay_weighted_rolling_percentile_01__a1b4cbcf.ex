defmodule DecayPercentile do
  @moduledoc """
  A `GenServer` that computes time-decay weighted rolling percentiles.

  Unlike a sliding window, samples never "expire" at a hard boundary. Instead
  each sample carries an exponentially decaying weight determined by its age:

      w_i = 0.5 ^ ((now - t_i) / half_life_ms)

  A freshly recorded sample has weight `1.0`, a sample one half-life old has
  weight `0.5`, two half-lives `0.25`, and so on. Percentiles are therefore
  smooth and drift-aware: there is no abrupt jump when a sample crosses an
  edge, because there is no edge.

  A single process manages many independent series, each keyed by an arbitrary
  term. Queries use the *weighted nearest-rank* method: samples are sorted
  ascending by value, weights are accumulated, and the first value whose
  cumulative weight reaches `p * total_weight` is returned. Because uniform
  aging scales every weight by the same factor, advancing the clock without
  recording anything leaves the reported percentile unchanged.

  Samples whose weight has underflowed to exactly zero (extremely old samples,
  where the float `0.5 ^ x` rounds to zero) are excluded from selection
  entirely and can never be returned at any percentile.

  ## Example

      {:ok, _pid} = DecayPercentile.start_link(half_life_ms: 60_000)
      :ok = DecayPercentile.record(:latency, 12)
      :ok = DecayPercentile.record(:latency, 97)
      {:ok, _p95} = DecayPercentile.query(:latency, 0.95)

  """

  use GenServer

  @type series :: term()
  @type sample :: {value :: number(), timestamp_ms :: integer()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:clock, :half_life_ms, :max_samples, :series]
    defstruct [:clock, :half_life_ms, :max_samples, :series]
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the server and registers it.

  ## Options

    * `:name` — name to register the process under. Defaults to
      `DecayPercentile`.
    * `:clock` — zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:half_life_ms` — **required** positive integer. The age at which a
      sample's weight halves. Any other value raises `ArgumentError`.
    * `:max_samples` — optional positive integer bounding the number of
      retained samples per series; the oldest are dropped first.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    clock = validate_clock!(Keyword.get(opts, :clock, &default_clock/0))
    half_life_ms = validate_half_life!(Keyword.get(opts, :half_life_ms))
    max_samples = validate_max_samples!(Keyword.get(opts, :max_samples))

    state = %State{
      clock: clock,
      half_life_ms: half_life_ms,
      max_samples: max_samples,
      series: %{}
    }

    GenServer.start_link(__MODULE__, state, name: name)
  end

  @doc """
  Records a numeric `value` into series `name`, stamped with the current clock.

  Always returns `:ok`.
  """
  @spec record(GenServer.server(), series(), number()) :: :ok
  def record(server \\ __MODULE__, name, value) when is_number(value) do
    GenServer.call(server, {:record, name, value})
  end

  @doc """
  Computes the weighted nearest-rank percentile of series `name`.

  `percentile` must be a float between `0.0` and `1.0` inclusive. Returns
  `{:ok, value}` where `value` is one of the recorded samples, or
  `{:error, :empty}` when the series holds no samples with a non-zero weight.
  """
  @spec query(GenServer.server(), series(), float()) :: {:ok, number()} | {:error, :empty}
  def query(server \\ __MODULE__, name, percentile)
      when is_float(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(server, {:query, name, percentile})
  end

  @doc """
  Returns `{:ok, weight}` with the sum of the current decayed weights of series
  `name`, or `{:error, :empty}` when the series holds no samples.

  The total weight acts as an "effective sample count" for inspection.
  """
  @spec total_weight(GenServer.server(), series()) :: {:ok, float()} | {:error, :empty}
  def total_weight(server \\ __MODULE__, name) do
    GenServer.call(server, {:total_weight, name})
  end

  @doc """
  Discards every sample recorded for series `name`. Always returns `:ok`.
  """
  @spec reset(GenServer.server(), series()) :: :ok
  def reset(server \\ __MODULE__, name) do
    GenServer.call(server, {:reset, name})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(%State{} = state), do: {:ok, state}

  @impl GenServer
  def handle_call({:record, name, value}, _from, %State{} = state) do
    now = now_ms(state)
    samples = Map.get(state.series, name, [])
    samples = trim(samples ++ [{value, now}], state.max_samples)
    {:reply, :ok, %State{state | series: Map.put(state.series, name, samples)}}
  end

  def handle_call({:query, name, percentile}, _from, %State{} = state) do
    weighted =
      state
      |> weighted_samples(name)
      |> Enum.filter(fn {_value, weight} -> weight > 0.0 end)

    {:reply, nearest_rank(weighted, percentile), state}
  end

  def handle_call({:total_weight, name}, _from, %State{} = state) do
    case weighted_samples(state, name) do
      [] ->
        {:reply, {:error, :empty}, state}

      weighted ->
        total = Enum.reduce(weighted, 0.0, fn {_value, weight}, acc -> acc + weight end)
        {:reply, {:ok, total}, state}
    end
  end

  def handle_call({:reset, name}, _from, %State{} = state) do
    {:reply, :ok, %State{state | series: Map.delete(state.series, name)}}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  @spec default_clock() :: integer()
  defp default_clock, do: System.monotonic_time(:millisecond)

  @spec now_ms(State.t()) :: integer()
  defp now_ms(%State{clock: clock}) do
    clock.()
  end

  @spec validate_clock!(term()) :: (-> integer())
  defp validate_clock!(clock) when is_function(clock, 0), do: clock

  defp validate_clock!(other) do
    raise ArgumentError, ":clock must be a zero-arity function, got: #{inspect(other)}"
  end

  @spec validate_half_life!(term()) :: pos_integer()
  defp validate_half_life!(half_life) when is_integer(half_life) and half_life > 0 do
    half_life
  end

  defp validate_half_life!(other) do
    raise ArgumentError,
          ":half_life_ms is required and must be a positive integer, got: #{inspect(other)}"
  end

  @spec validate_max_samples!(term()) :: pos_integer() | nil
  defp validate_max_samples!(nil), do: nil

  defp validate_max_samples!(max) when is_integer(max) and max > 0, do: max

  defp validate_max_samples!(other) do
    raise ArgumentError,
          ":max_samples must be a positive integer or nil, got: #{inspect(other)}"
  end

  # Samples are kept oldest-first, so dropping the oldest is a prefix drop.
  @spec trim([sample()], pos_integer() | nil) :: [sample()]
  defp trim(samples, nil), do: samples

  defp trim(samples, max) do
    excess = length(samples) - max

    if excess > 0 do
      Enum.drop(samples, excess)
    else
      samples
    end
  end

  @spec weighted_samples(State.t(), series()) :: [{number(), float()}]
  defp weighted_samples(%State{} = state, name) do
    now = now_ms(state)

    state.series
    |> Map.get(name, [])
    |> Enum.map(fn {value, timestamp} ->
      {value, decay_weight(now - timestamp, state.half_life_ms)}
    end)
  end

  @spec decay_weight(integer(), pos_integer()) :: float()
  defp decay_weight(age_ms, half_life_ms) do
    :math.pow(0.5, age_ms / half_life_ms)
  end

  # Weighted nearest-rank: sort ascending by value, accumulate weight, return the
  # first value whose cumulative weight reaches `p * total_weight`.
  @spec nearest_rank([{number(), float()}], float()) :: {:ok, number()} | {:error, :empty}
  defp nearest_rank([], _percentile), do: {:error, :empty}

  defp nearest_rank(weighted, percentile) do
    total = Enum.reduce(weighted, 0.0, fn {_value, weight}, acc -> acc + weight end)

    case total do
      +0.0 ->
        {:error, :empty}

      total ->
        target = percentile * total
        sorted = Enum.sort_by(weighted, fn {value, _weight} -> value end)
        {:ok, walk(sorted, target, 0.0)}
    end
  end

  @spec walk([{number(), float()}, ...], float(), float()) :: number()
  defp walk([{value, _weight}], _target, _acc), do: value

  defp walk([{value, weight} | rest], target, acc) do
    acc = acc + weight

    if acc >= target do
      value
    else
      walk(rest, target, acc)
    end
  end
end
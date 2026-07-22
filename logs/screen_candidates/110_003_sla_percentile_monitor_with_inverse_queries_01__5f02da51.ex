defmodule RankPercentile do
  @moduledoc """
  A GenServer maintaining rolling windows of numeric samples across many
  independent series, answering both forward and inverse rank queries.

  Forward: `query/2` returns the value at a requested percentile using the
  nearest-rank method. Inverse: `rank/2` returns the empirical CDF at a value,
  and `count_above/2` returns the number of samples strictly above a threshold.

  Together these make an SLA/latency monitor: `query/2` gives the pXX latency,
  `rank/2` gives "what fraction of requests came in at or under X", and
  `count_above/2` gives the raw count of SLA violations.

  Each series is identified by an arbitrary term and keeps its samples in a
  rolling window that may be time-based (`:window_ms`), count-based
  (`:max_samples`), both, or neither (unbounded).

  Samples are stored per series as a list of `{value, timestamp}` pairs kept in
  ascending order of `value`, so percentile queries need no sort at query time.
  Time-based expiration is applied lazily, at query time.
  """

  use GenServer

  @type series :: term()
  @type sample :: {number(), integer()}

  defmodule State do
    @moduledoc false

    defstruct clock: nil, window_ms: nil, max_samples: nil, series: %{}
  end

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the monitor process and registers it.

  ## Options

    * `:name` — name to register under. Defaults to `RankPercentile`.
    * `:clock` — zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:window_ms` — positive integer enabling a time-based window; a sample
      recorded at `t` is live while `now - t < window_ms`.
    * `:max_samples` — positive integer enabling a count-based window; only the
      most recent N samples per series are retained.

  Both windows may be combined, in which case both apply.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records `value` into the series `name`, timestamped with the current clock.

  Always returns `:ok`.
  """
  @spec record(series(), number()) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.cast(server(), {:record, name, value})
  end

  @doc """
  Returns `{:ok, value}` for the requested `percentile` of the live samples in
  series `name`, or `{:error, :empty}` when the series has no live samples.

  Uses the nearest-rank method: `rank = max(1, ceil(percentile * n))`, and the
  value returned is the one at that 1-indexed rank in ascending order — always
  one of the recorded samples. `percentile` must be a float in `0.0..1.0`.
  """
  @spec query(series(), float()) :: {:ok, number()} | {:error, :empty}
  def query(name, percentile)
      when is_float(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(server(), {:query, name, percentile})
  end

  @doc """
  Returns `{:ok, q}` where `q` is the fraction of live samples in series `name`
  that are less than or equal to `value` — the empirical CDF at `value`, a float
  in `0.0..1.0`.

  A `value` below the minimum yields `0.0`; a `value` at or above the maximum
  yields `1.0`. Returns `{:error, :empty}` when the series has no live samples.
  """
  @spec rank(series(), number()) :: {:ok, float()} | {:error, :empty}
  def rank(name, value) when is_number(value) do
    GenServer.call(server(), {:rank, name, value})
  end

  @doc """
  Returns `{:ok, count}` with the number of live samples in series `name` that
  are strictly greater than `threshold`.

  An empty or unknown series yields `{:ok, 0}` rather than an error.
  """
  @spec count_above(series(), number()) :: {:ok, non_neg_integer()}
  def count_above(name, threshold) when is_number(threshold) do
    GenServer.call(server(), {:count_above, name, threshold})
  end

  @doc """
  Discards all samples recorded for series `name`. Always returns `:ok`.
  """
  @spec reset(series()) :: :ok
  def reset(name) do
    GenServer.call(server(), {:reset, name})
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    window_ms = Keyword.get(opts, :window_ms)
    max_samples = Keyword.get(opts, :max_samples)

    with :ok <- validate_clock(clock),
         :ok <- validate_limit(:window_ms, window_ms),
         :ok <- validate_limit(:max_samples, max_samples) do
      {:ok, %State{clock: clock, window_ms: window_ms, max_samples: max_samples}}
    end
  end

  @impl true
  def handle_cast({:record, name, value}, state) do
    now = state.clock.()

    samples =
      state.series
      |> Map.get(name, [])
      |> live(now, state.window_ms)
      |> insert({value, now})
      |> cap(state.max_samples)

    {:noreply, %State{state | series: Map.put(state.series, name, samples)}}
  end

  @impl true
  def handle_call({:query, name, percentile}, _from, state) do
    {samples, state} = fetch_live(state, name)

    case length(samples) do
      0 ->
        {:reply, {:error, :empty}, state}

      n ->
        rank = max(1, ceil(percentile * n))
        {value, _ts} = Enum.at(samples, rank - 1)
        {:reply, {:ok, value}, state}
    end
  end

  def handle_call({:rank, name, value}, _from, state) do
    {samples, state} = fetch_live(state, name)

    case length(samples) do
      0 ->
        {:reply, {:error, :empty}, state}

      n ->
        at_or_below = Enum.count(samples, fn {v, _ts} -> v <= value end)
        {:reply, {:ok, at_or_below / n}, state}
    end
  end

  def handle_call({:count_above, name, threshold}, _from, state) do
    {samples, state} = fetch_live(state, name)
    count = Enum.count(samples, fn {v, _ts} -> v > threshold end)
    {:reply, {:ok, count}, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %State{state | series: Map.delete(state.series, name)}}
  end

  # --------------------------------------------------------------------------
  # Internals
  # --------------------------------------------------------------------------

  defp server, do: __MODULE__

  # Returns the live samples for `name` and a state with expiration applied,
  # so repeated queries do not rescan already-expired samples.
  defp fetch_live(state, name) do
    case Map.fetch(state.series, name) do
      :error ->
        {[], state}

      {:ok, samples} ->
        case live(samples, state.clock.(), state.window_ms) do
          [] -> {[], %State{state | series: Map.delete(state.series, name)}}
          kept -> {kept, %State{state | series: Map.put(state.series, name, kept)}}
        end
    end
  end

  defp live(samples, _now, nil), do: samples

  defp live(samples, now, window_ms) do
    Enum.filter(samples, fn {_v, ts} -> now - ts < window_ms end)
  end

  # Inserts into a list kept ascending by value; ties keep insertion order
  # among equal values, which is irrelevant to every query but stable.
  defp insert([], sample), do: [sample]

  defp insert([{head_v, _} = head | tail], {value, _} = sample) do
    if value < head_v do
      [sample, head | tail]
    else
      [head | insert(tail, sample)]
    end
  end

  defp cap(samples, nil), do: samples

  defp cap(samples, max_samples) do
    excess = length(samples) - max_samples

    if excess > 0 do
      drop_oldest(samples, excess)
    else
      samples
    end
  end

  # Drops the `n` oldest samples by timestamp while preserving value ordering.
  defp drop_oldest(samples, n) do
    cutoff =
      samples
      |> Enum.map(fn {_v, ts} -> ts end)
      |> Enum.sort()
      |> Enum.take(n)
      |> List.last()

    doomed = Enum.count(samples, fn {_v, ts} -> ts < cutoff end)
    drop_at_cutoff = n - doomed

    {kept, _left} =
      Enum.map_reduce(samples, drop_at_cutoff, fn
        {_v, ts} = sample, left when ts < cutoff -> {nil, left}
        {_v, ts} = sample, left when ts == cutoff and left > 0 -> {nil, left - 1}
        sample, left -> {sample, left}
      end)

    Enum.reject(kept, &is_nil/1)
  end

  defp validate_clock(clock) when is_function(clock, 0), do: :ok
  defp validate_clock(_clock), do: {:stop, {:bad_option, :clock}}

  defp validate_limit(_key, nil), do: :ok
  defp validate_limit(_key, value) when is_integer(value) and value > 0, do: :ok
  defp validate_limit(key, _value), do: {:stop, {:bad_option, key}}
end
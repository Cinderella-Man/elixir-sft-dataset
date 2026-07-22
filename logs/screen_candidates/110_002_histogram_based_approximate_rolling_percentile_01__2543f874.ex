defmodule HistogramPercentile do
  @moduledoc """
  Approximate rolling-window percentile estimation backed by fixed-edge histograms.

  A single `GenServer` process manages many independent *series*, each identified by an
  arbitrary term. Instead of retaining every raw sample, each series stores a ring buffer
  of `:slots` per-time-slice histograms over a shared, caller-supplied set of bucket edges.
  Memory per series is therefore bounded by `slots * buckets` counters regardless of how
  many samples are recorded.

  The rolling window is applied lazily at query time: a stored slice contributes only when
  `now - slice_start < window_ms`. Each slot records the time slice that wrote it, so a
  stale slot is ignored even if it has not yet been overwritten by a later cycle.

  Percentiles are estimated with Prometheus-style linear interpolation inside the selected
  bucket, so the error is bounded by the width of that bucket.

  ## Example

      {:ok, _pid} = HistogramPercentile.start_link(edges: [0, 10, 100], window_ms: 1_000)
      :ok = HistogramPercentile.record(:latency, 5)
      {:ok, estimate} = HistogramPercentile.query(:latency, 0.95)
  """

  use GenServer

  @default_slots 60

  @typedoc "Identifier of an independent series; any term."
  @type series :: term()

  @typedoc "A percentile expressed as a float in the inclusive range `0.0..1.0`."
  @type percentile :: float()

  defmodule State do
    @moduledoc false
    defstruct [:clock, :edges, :buckets, :window_ms, :slots, :slot_ms, series: %{}]
  end

  @doc """
  Starts and registers the histogram percentile server.

  Options:

    * `:name` — registration name, defaults to `HistogramPercentile`.
    * `:clock` — zero-arity function returning milliseconds, defaults to
      `fn -> System.monotonic_time(:millisecond) end`.
    * `:edges` — required strictly increasing list of at least two numbers.
    * `:window_ms` — required positive integer rolling window size.
    * `:slots` — positive integer number of time slices, defaults to `60`.

  Invalid options raise `ArgumentError` synchronously in the calling process, before any
  server is spawned.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    state = build_state!(opts)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, state, name: name)
  end

  @doc """
  Records `value` into the current time slice of `series`.

  The value is clamped into the first or last bucket when it falls outside the configured
  edges. Always returns `:ok`.
  """
  @spec record(series(), number()) :: :ok
  def record(series, value) when is_number(value) do
    GenServer.cast(__MODULE__, {:record, series, value})
  end

  @doc """
  Estimates the `percentile` of the live samples of `series`.

  Returns `{:ok, estimate}` with a float estimate, or `{:error, :empty}` when the series
  holds no counts inside the rolling window.
  """
  @spec query(series(), percentile()) :: {:ok, float()} | {:error, :empty}
  def query(series, percentile) when is_number(percentile) and percentile >= 0 and percentile <= 1 do
    GenServer.call(__MODULE__, {:query, series, percentile * 1.0})
  end

  @doc """
  Discards every stored count for `series`. Returns `:ok`.
  """
  @spec reset(series()) :: :ok
  def reset(series) do
    GenServer.call(__MODULE__, {:reset, series})
  end

  @impl GenServer
  def init(%State{} = state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:record, series, value}, %State{} = state) do
    now = state.clock.()
    slice = div_floor(now, state.slot_ms)
    slot = Integer.mod(slice, state.slots)
    index = bucket_index(state.edges, value)

    ring = Map.get(state.series, series, %{})

    counts =
      case Map.get(ring, slot) do
        {^slice, counts} -> counts
        _other -> empty_counts(state.buckets)
      end

    counts = Map.update(counts, index, 1, &(&1 + 1))
    ring = Map.put(ring, slot, {slice, counts})
    {:noreply, %State{state | series: Map.put(state.series, series, ring)}}
  end

  @impl GenServer
  def handle_call({:query, series, percentile}, _from, %State{} = state) do
    now = state.clock.()
    ring = Map.get(state.series, series, %{})
    totals = live_totals(ring, now, state)
    {:reply, estimate(totals, percentile, state), state}
  end

  def handle_call({:reset, series}, _from, %State{} = state) do
    {:reply, :ok, %State{state | series: Map.delete(state.series, series)}}
  end

  # -- option validation -------------------------------------------------------------

  defp build_state!(opts) do
    edges = validate_edges!(Keyword.get(opts, :edges))
    window_ms = validate_window!(Keyword.get(opts, :window_ms))
    slots = validate_slots!(Keyword.get(opts, :slots, @default_slots))
    clock = validate_clock!(Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end))

    %State{
      clock: clock,
      edges: edges,
      buckets: length(edges) - 1,
      window_ms: window_ms,
      slots: slots,
      slot_ms: max(div(window_ms, slots), 1)
    }
  end

  defp validate_edges!(edges) when is_list(edges) and length(edges) >= 2 do
    unless Enum.all?(edges, &is_number/1) do
      raise ArgumentError, ":edges must be a list of numbers"
    end

    unless edges |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> a < b end) do
      raise ArgumentError, ":edges must be strictly increasing"
    end

    edges
  end

  defp validate_edges!(other) do
    raise ArgumentError,
          ":edges must be a strictly increasing list of at least two numbers, got: " <>
            inspect(other)
  end

  defp validate_window!(window) when is_integer(window) and window > 0, do: window

  defp validate_window!(other) do
    raise ArgumentError, ":window_ms must be a positive integer, got: #{inspect(other)}"
  end

  defp validate_slots!(slots) when is_integer(slots) and slots > 0, do: slots

  defp validate_slots!(other) do
    raise ArgumentError, ":slots must be a positive integer, got: #{inspect(other)}"
  end

  defp validate_clock!(clock) when is_function(clock, 0), do: clock

  defp validate_clock!(other) do
    raise ArgumentError, ":clock must be a zero-arity function, got: #{inspect(other)}"
  end

  # -- histogram helpers -------------------------------------------------------------

  defp empty_counts(_buckets), do: %{}

  defp bucket_index(edges, value) do
    last = length(edges) - 2

    edges
    |> Enum.drop(1)
    |> Enum.take(last + 1)
    |> Enum.find_index(fn edge -> value < edge end)
    |> case do
      nil -> last
      index -> index
    end
  end

  defp live_totals(ring, now, %State{} = state) do
    Enum.reduce(ring, %{}, fn {_slot, {slice, counts}}, acc ->
      if live?(slice, now, state) do
        Map.merge(acc, counts, fn _index, a, b -> a + b end)
      else
        acc
      end
    end)
  end

  defp live?(slice, now, %State{} = state) do
    slice_start = slice * state.slot_ms
    now - slice_start < state.window_ms and now - slice_start >= 0
  end

  defp estimate(totals, percentile, %State{} = state) do
    n = totals |> Map.values() |> Enum.sum()

    if n == 0 do
      {:error, :empty}
    else
      counts = Enum.map(0..(state.buckets - 1), &Map.get(totals, &1, 0))
      {:ok, interpolate(counts, percentile * n, state.edges, state.buckets)}
    end
  end

  defp interpolate(counts, target, edges, buckets) do
    {index, cum_before, count} = select_bucket(counts, target, buckets - 1)
    lo = Enum.at(edges, index) * 1.0
    hi = Enum.at(edges, index + 1) * 1.0
    frac = if count == 0, do: +0.0, else: (target - cum_before) / count
    lo + (hi - lo) * clamp(frac)
  end

  defp select_bucket(counts, target, last_index) do
    counts
    |> Enum.with_index()
    |> Enum.reduce_while({last_index, 0, 0}, fn {count, index}, {_i, cum_before, _c} ->
      cond do
        index == last_index -> {:halt, {index, cum_before, count}}
        cum_before + count >= target -> {:halt, {index, cum_before, count}}
        true -> {:cont, {index, cum_before + count, count}}
      end
    end)
  end

  defp clamp(frac) when frac < 0.0, do: +0.0
  defp clamp(frac) when frac > 1.0, do: 1.0
  defp clamp(frac), do: frac

  defp div_floor(value, divisor), do: Integer.floor_div(value, divisor)
end
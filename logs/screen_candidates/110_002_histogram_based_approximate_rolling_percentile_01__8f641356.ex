defmodule HistogramPercentile do
  @moduledoc """
  Approximate rolling-window percentile estimation backed by fixed bucket histograms.

  A single process manages many independent *series*, each keyed by an arbitrary term.
  Instead of retaining every raw sample (which grows without bound), each series keeps a
  ring buffer of per-time-slice histograms over a user-supplied set of bucket edges. Memory
  per series is therefore bounded by `slots * bucket_count`, regardless of sample volume.

  ## Buckets

  Given strictly increasing `edges = [e0, e1, ..., ek]`, bucket `i` covers `[e_i, e_{i+1})`
  and the final bucket `[e_{k-1}, ek]` is closed. Values below `e0` are clamped into the
  first bucket; values at or above `ek` are clamped into the last one.

  ## Windowing

  The window is split into `slots` time slices. A sample recorded at time `t` lands in the
  slice starting at `div(t, slice_ms) * slice_ms`, stored in ring slot
  `rem(div(t, slice_ms), slots)`. When a slot is reused by a newer slice, its stale counts
  are dropped. Expiry is evaluated lazily at query time, so simply advancing the clock and
  re-querying reflects newly expired slices.

  ## Estimation

  Queries sum the live slices' bucket counts and apply Prometheus-style linear
  interpolation within the chosen bucket. Results are approximate; the error is bounded by
  the width of the bucket containing the true quantile.
  """

  use GenServer

  @default_slots 60

  @typedoc "Identifier of a series; any term."
  @type series :: term()

  @typedoc "The registered name of a running `HistogramPercentile` process."
  @type server :: GenServer.server()

  defmodule Series do
    @moduledoc false
    # slices: %{slot_index => {slice_start_ms, counts_tuple}}
    defstruct slices: %{}
  end

  # ── Public API ────────────────────────────────────────────────────────────────────────

  @doc """
  Starts and registers the histogram percentile server.

  ## Options

    * `:name` — registration name. Defaults to `HistogramPercentile`.
    * `:clock` — zero-arity function returning the current time in milliseconds. Defaults
      to `fn -> System.monotonic_time(:millisecond) end`.
    * `:edges` — required strictly increasing list of at least two numbers.
    * `:window_ms` — required positive integer window length.
    * `:slots` — positive integer number of time slices. Defaults to `60`.

  Raises `ArgumentError` when any option is invalid.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records `value` into the current time slice of series `name`.

  The value is clamped into the first or last bucket when it falls outside the edge range.
  Always returns `:ok`.
  """
  @spec record(server(), series(), number()) :: :ok
  def record(server \\ __MODULE__, name, value) when is_number(value) do
    GenServer.cast(server, {:record, name, value})
  end

  @doc """
  Estimates the given `percentile` (a float in `0.0..1.0`) over the live window of `name`.

  Returns `{:ok, estimate}` with a float estimate, or `{:error, :empty}` when no live
  counts exist for the series.
  """
  @spec query(server(), series(), float()) :: {:ok, float()} | {:error, :empty}
  def query(server \\ __MODULE__, name, percentile)
      when is_float(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(server, {:query, name, percentile})
  end

  @doc """
  Discards all recorded counts for series `name`. Returns `:ok`.
  """
  @spec reset(server(), series()) :: :ok
  def reset(server \\ __MODULE__, name) do
    GenServer.call(server, {:reset, name})
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    edges = validate_edges!(Keyword.fetch!(opts, :edges))
    window_ms = validate_window!(Keyword.fetch!(opts, :window_ms))
    slots = validate_slots!(Keyword.get(opts, :slots, @default_slots))
    clock = validate_clock!(Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end))

    bucket_count = length(edges) - 1

    state = %{
      edges: List.to_tuple(edges),
      bucket_count: bucket_count,
      empty_counts: Tuple.duplicate(0, bucket_count),
      window_ms: window_ms,
      slots: slots,
      slice_ms: slice_ms(window_ms, slots),
      clock: clock,
      series: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:record, name, value}, state) do
    now = state.clock.()
    index = bucket_index(state.edges, state.bucket_count, value)
    cycle = floor_div(now, state.slice_ms)
    slot = Integer.mod(cycle, state.slots)
    slice_start = cycle * state.slice_ms

    series = Map.get(state.series, name, %Series{})

    counts =
      case Map.get(series.slices, slot) do
        {^slice_start, counts} -> counts
        _stale_or_missing -> state.empty_counts
      end

    counts = put_elem(counts, index, elem(counts, index) + 1)
    slices = Map.put(series.slices, slot, {slice_start, counts})
    series = %Series{series | slices: slices}

    {:noreply, %{state | series: Map.put(state.series, name, series)}}
  end

  @impl true
  def handle_call({:query, name, percentile}, _from, state) do
    now = state.clock.()

    reply =
      case Map.fetch(state.series, name) do
        {:ok, series} -> estimate(series, percentile, now, state)
        :error -> {:error, :empty}
      end

    {:reply, reply, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  # ── Option validation ─────────────────────────────────────────────────────────────────

  defp validate_edges!(edges) when is_list(edges) and length(edges) >= 2 do
    unless Enum.all?(edges, &is_number/1) do
      raise ArgumentError, ":edges must be a list of numbers, got: #{inspect(edges)}"
    end

    unless strictly_increasing?(edges) do
      raise ArgumentError, ":edges must be strictly increasing, got: #{inspect(edges)}"
    end

    edges
  end

  defp validate_edges!(other) do
    raise ArgumentError,
          ":edges must be a strictly increasing list of at least two numbers, " <>
            "got: #{inspect(other)}"
  end

  defp strictly_increasing?([_only]), do: true
  defp strictly_increasing?([a, b | rest]) when a < b, do: strictly_increasing?([b | rest])
  defp strictly_increasing?(_other), do: false

  defp validate_window!(window_ms) when is_integer(window_ms) and window_ms > 0, do: window_ms

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

  # ── Internals ─────────────────────────────────────────────────────────────────────────

  defp slice_ms(window_ms, slots) do
    max(div(window_ms + slots - 1, slots), 1)
  end

  # Floor division that also behaves for negative timestamps (monotonic time may be < 0).
  defp floor_div(a, b), do: Integer.floor_div(a, b)

  defp bucket_index(edges, bucket_count, value) do
    cond do
      value <= elem(edges, 0) -> 0
      value >= elem(edges, bucket_count) -> bucket_count - 1
      true -> search_bucket(edges, value, 0, bucket_count - 1)
    end
  end

  # Binary search for the bucket i where edges[i] <= value < edges[i + 1].
  defp search_bucket(_edges, _value, low, high) when low >= high, do: low

  defp search_bucket(edges, value, low, high) do
    mid = div(low + high + 1, 2)

    if elem(edges, mid) <= value do
      search_bucket(edges, value, mid, high)
    else
      search_bucket(edges, value, low, mid - 1)
    end
  end

  defp estimate(series, percentile, now, state) do
    counts = live_counts(series, now, state)
    total = Enum.sum(counts)

    if total == 0 do
      {:error, :empty}
    else
      {:ok, interpolate(counts, percentile * total, state.edges)}
    end
  end

  defp live_counts(series, now, state) do
    series.slices
    |> Enum.reduce(state.empty_counts, fn {_slot, {slice_start, counts}}, acc ->
      if now - slice_start < state.window_ms and now - slice_start >= 0 do
        merge_counts(acc, counts, state.bucket_count)
      else
        acc
      end
    end)
    |> Tuple.to_list()
  end

  defp merge_counts(acc, counts, bucket_count) do
    Enum.reduce(0..(bucket_count - 1)//1, acc, fn i, acc ->
      put_elem(acc, i, elem(acc, i) + elem(counts, i))
    end)
  end

  # Prometheus-style linear interpolation within the selected bucket.
  defp interpolate(counts, target, edges) do
    {index, cum_before, count} = select_bucket(counts, target)

    lo = elem(edges, index) * 1.0
    hi = elem(edges, index + 1) * 1.0

    frac =
      if count == 0 do
        +0.0
      else
        clamp((target - cum_before) / count)
      end

    lo + (hi - lo) * frac
  end

  defp select_bucket(counts, target) do
    last_index = length(counts) - 1

    Enum.reduce_while(Enum.with_index(counts), 0, fn {count, index}, cum_before ->
      if cum_before + count >= target or index == last_index do
        {:halt, {index, cum_before, count}}
      else
        {:cont, cum_before + count}
      end
    end)
  end

  defp clamp(frac) when frac < 0.0, do: +0.0
  defp clamp(frac) when frac > 1.0, do: 1.0
  defp clamp(frac), do: frac
end
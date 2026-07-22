defmodule HistogramPercentile do
  @moduledoc """
  A GenServer that estimates percentiles over a rolling time window using a
  fixed bucket histogram, trading exactness for bounded memory.

  A single process manages many independent series. Each series keeps a ring
  buffer of `:slots` per-time-slice histograms, where a histogram is a map of
  `bucket_index => count`, so memory stays bounded no matter how many samples
  arrive. Percentiles are estimated at query time with Prometheus-style linear
  interpolation over the buckets of every slice still inside the window.
  """

  use GenServer

  @default_name HistogramPercentile
  @default_slots 60

  ## Public API

  @doc """
  Starts the server and registers it under `:name` (default
  `HistogramPercentile`).

  Options:

    * `:edges` — required, a strictly increasing list of at least two numbers.
    * `:window_ms` — required positive integer window length.
    * `:slots` — positive integer number of time slices, default
      `#{@default_slots}`.
    * `:clock` — zero-arity function returning the current time in
      milliseconds, default `System.monotonic_time(:millisecond)`.

  Options are validated eagerly in the calling process, so invalid options
  raise `ArgumentError` out of `start_link/1` itself instead of taking the
  caller down through a linked-process exit from `init/1`.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, build_config(opts), name: name)
  end

  @doc """
  Records `value` into the current time slice of series `series`.

  Values below the first edge are clamped into bucket 0 and values at or above
  the last edge are clamped into the final bucket. Returns `:ok`.
  """
  @spec record(term, number) :: :ok
  def record(series, value) when is_number(value) do
    GenServer.call(@default_name, {:record, series, value})
  end

  @doc """
  Estimates `percentile` (a number in `0.0..1.0`) over the live window of
  series `series`.

  Returns `{:ok, float}`, or `{:error, :empty}` when no counts remain inside
  the window.
  """
  @spec query(term, float) :: {:ok, float} | {:error, :empty}
  def query(series, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, series, percentile})
  end

  @doc "Discards every stored count for series `series`. Returns `:ok`."
  @spec reset(term) :: :ok
  def reset(series), do: GenServer.call(@default_name, {:reset, series})

  ## GenServer callbacks

  @impl true
  def init(config), do: {:ok, config}

  @impl true
  def handle_call({:record, series, value}, _from, state) do
    now = state.clock.()
    slice_index = div(now, state.slice_ms)
    slice_start = slice_index * state.slice_ms
    slot = rem(slice_index, state.slots)

    histograms = Map.get(state.series, series, %{})

    counts =
      case Map.get(histograms, slot) do
        {^slice_start, counts} -> counts
        _reused_or_missing -> %{}
      end

    bucket = bucket_index(value, state.ranges)
    counts = Map.update(counts, bucket, 1, &(&1 + 1))
    histograms = Map.put(histograms, slot, {slice_start, counts})

    {:reply, :ok, %{state | series: Map.put(state.series, series, histograms)}}
  end

  def handle_call({:query, series, percentile}, _from, state) do
    now = state.clock.()

    merged =
      state.series
      |> Map.get(series, %{})
      |> Map.values()
      |> Enum.filter(fn {slice_start, _counts} -> now - slice_start < state.window_ms end)
      |> Enum.reduce(%{}, fn {_slice_start, counts}, acc -> merge_counts(acc, counts) end)

    {:reply, quantile(merged, state.ranges, percentile), state}
  end

  def handle_call({:reset, series}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, series)}}
  end

  ## Configuration

  defp build_config(opts) do
    edges = validate_edges(Keyword.get(opts, :edges))
    window_ms = validate_positive(Keyword.get(opts, :window_ms), :window_ms)
    slots = validate_positive(Keyword.get(opts, :slots, @default_slots), :slots)
    default_clock = fn -> System.monotonic_time(:millisecond) end

    %{
      clock: Keyword.get(opts, :clock, default_clock),
      ranges: bucket_ranges(edges),
      window_ms: window_ms,
      slots: slots,
      slice_ms: max(1, div(window_ms + slots - 1, slots)),
      series: %{}
    }
  end

  defp bucket_ranges(edges) do
    edges
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [lo, hi] -> {lo, hi} end)
  end

  ## Estimation

  defp quantile(counts, ranges, percentile) do
    tallies =
      ranges
      |> Enum.with_index()
      |> Enum.map(fn {{lo, hi}, i} -> {lo, hi, Map.get(counts, i, 0)} end)

    n = Enum.reduce(tallies, 0, fn {_lo, _hi, c}, acc -> acc + c end)

    if n == 0 do
      {:error, :empty}
    else
      target = percentile * n
      {lo, hi, c, cum_before} = locate(tallies, 0, target)
      frac = if c == 0, do: 0.0, else: (target - cum_before) / c
      frac = frac |> max(0.0) |> min(1.0)
      {:ok, (lo + (hi - lo) * frac) * 1.0}
    end
  end

  defp locate([{lo, hi, c}], cum_before, _target), do: {lo, hi, c, cum_before}

  defp locate([{lo, hi, c} | rest], cum_before, target) do
    if cum_before + c >= target do
      {lo, hi, c, cum_before}
    else
      locate(rest, cum_before + c, target)
    end
  end

  defp bucket_index(value, ranges) do
    {low_edge, _hi} = hd(ranges)
    {_lo, high_edge} = List.last(ranges)
    clamped = value |> max(low_edge) |> min(high_edge)
    find_bucket(Enum.with_index(ranges), clamped)
  end

  defp find_bucket([{{_lo, _hi}, i}], _value), do: i

  defp find_bucket([{{_lo, hi}, i} | rest], value) do
    if value < hi, do: i, else: find_bucket(rest, value)
  end

  defp merge_counts(acc, counts), do: Map.merge(acc, counts, fn _k, a, b -> a + b end)

  ## Validation

  defp validate_edges(edges) when is_list(edges) and length(edges) >= 2 do
    numbers? = Enum.all?(edges, &is_number/1)

    increasing? =
      edges
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [a, b] -> b > a end)

    if numbers? and increasing? do
      edges
    else
      raise ArgumentError,
            ":edges must be a strictly increasing list of numbers, got: #{inspect(edges)}"
    end
  end

  defp validate_edges(other) do
    raise ArgumentError,
          ":edges must be a strictly increasing list of >= 2 numbers, got: #{inspect(other)}"
  end

  defp validate_positive(n, _name) when is_integer(n) and n > 0, do: n

  defp validate_positive(other, name) do
    raise ArgumentError, "#{inspect(name)} must be a positive integer, got: #{inspect(other)}"
  end
end

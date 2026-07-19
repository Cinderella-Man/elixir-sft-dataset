# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule HistogramPercentile do
  @moduledoc """
  A GenServer that estimates percentiles over a rolling time window using a
  fixed bucket histogram, trading exactness for bounded memory.

  Each series stores a ring buffer of `:slots` per-time-slice histograms; every
  histogram is a map of `bucket_index => count`. Percentiles are estimated with
  Prometheus-style linear interpolation across the live buckets.
  """

  use GenServer

  @default_name HistogramPercentile

  ## Public API

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)

    # Validate eagerly in the caller process. If we let `init/1` raise instead,
    # the freshly-spawned (and linked) GenServer would exit with a non-normal
    # reason and take the caller down with it, rather than surfacing a clean
    # ArgumentError.
    _ = validate_edges(Keyword.get(opts, :edges))
    _ = validate_positive(Keyword.fetch!(opts, :window_ms), :window_ms)
    _ = validate_positive(Keyword.get(opts, :slots, 60), :slots)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Records `value` into the rolling histogram for `name`. Returns `:ok`."
  @spec record(term, number) :: :ok
  def record(name, value) when is_number(value) do
    GenServer.call(@default_name, {:record, name, value})
  end

  @spec query(term, float) :: {:ok, float} | {:error, :empty}
  def query(name, percentile)
      when is_number(percentile) and percentile >= 0.0 and percentile <= 1.0 do
    GenServer.call(@default_name, {:query, name, percentile})
  end

  @spec reset(term) :: :ok
  def reset(name), do: GenServer.call(@default_name, {:reset, name})

  ## GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    edges = validate_edges(Keyword.get(opts, :edges))
    window_ms = validate_positive(Keyword.fetch!(opts, :window_ms), :window_ms)
    slots = validate_positive(Keyword.get(opts, :slots, 60), :slots)
    slice_ms = max(1, div(window_ms + slots - 1, slots))

    {:ok,
     %{
       clock: clock,
       edges: edges,
       edges_t: List.to_tuple(edges),
       bucket_count: length(edges) - 1,
       window_ms: window_ms,
       slots: slots,
       slice_ms: slice_ms,
       series: %{}
     }}
  end

  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    slice_index = div(now, state.slice_ms)
    slice_start = slice_index * state.slice_ms
    slot = rem(slice_index, state.slots)

    series = Map.get(state.series, name, %{})

    counts =
      case Map.get(series, slot) do
        {^slice_start, c} -> c
        _ -> %{}
      end

    bucket = bucket_index(value, state.edges_t, state.bucket_count)
    counts = Map.update(counts, bucket, 1, &(&1 + 1))
    series = Map.put(series, slot, {slice_start, counts})

    {:reply, :ok, %{state | series: Map.put(state.series, name, series)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    now = state.clock.()

    merged =
      state.series
      |> Map.get(name, %{})
      |> Map.values()
      |> Enum.filter(fn {slice_start, _} -> now - slice_start < state.window_ms end)
      |> Enum.reduce(%{}, fn {_s, c}, acc -> merge_counts(acc, c) end)

    result = quantile(merged, state.edges_t, state.bucket_count, percentile)
    {:reply, result, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end

  ## Helpers

  defp quantile(counts, edges_t, k, percentile) do
    list = for i <- 0..(k - 1), do: Map.get(counts, i, 0)
    n = Enum.sum(list)

    if n == 0 do
      {:error, :empty}
    else
      target = percentile * n

      {value, _} =
        Enum.reduce_while(0..(k - 1), {nil, 0}, fn i, {_last, cum_before} ->
          c = Enum.at(list, i)
          cum = cum_before + c

          if cum >= target or i == k - 1 do
            lo = elem(edges_t, i)
            hi = elem(edges_t, i + 1)
            frac = if c == 0, do: 0.0, else: (target - cum_before) / c
            frac = frac |> max(0.0) |> min(1.0)
            {:halt, {lo + (hi - lo) * frac, cum}}
          else
            {:cont, {nil, cum}}
          end
        end)

      {:ok, value * 1.0}
    end
  end

  defp bucket_index(value, edges_t, k) do
    lo = elem(edges_t, 0)
    hi = elem(edges_t, k)
    v = value |> max(lo) |> min(hi)

    Enum.reduce_while(0..(k - 1), k - 1, fn i, _acc ->
      upper = elem(edges_t, i + 1)
      if v < upper, do: {:halt, i}, else: {:cont, min(i + 1, k - 1)}
    end)
  end

  defp merge_counts(acc, c), do: Map.merge(acc, c, fn _k, a, b -> a + b end)

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
```

## Test harness — implement the `# TODO` test

```elixir
defmodule HistogramPercentileTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  setup do
    start_supervised!({Clock, 0})
    :ok
  end

  defp start_server(opts) do
    opts =
      opts
      |> Keyword.put_new(:clock, &Clock.now/0)
      |> Keyword.put_new(:edges, Enum.map(0..10, &(&1 * 10)))
      |> Keyword.put_new(:window_ms, 1_000)
      |> Keyword.put_new(:slots, 10)

    start_supervised!({HistogramPercentile, opts})
    :ok
  end

  # ---------------------------------------------------------
  # Approximate quantile correctness
  # ---------------------------------------------------------

  test "histogram quantile estimates are deterministic for a known distribution" do
    start_server([])

    for v <- 1..100, do: assert(:ok = HistogramPercentile.record(:d, v))

    assert {:ok, p50} = HistogramPercentile.query(:d, 0.50)
    assert_in_delta p50, 51.0, 0.001

    assert {:ok, p95} = HistogramPercentile.query(:d, 0.95)
    assert_in_delta p95, 95.4545, 0.05

    assert {:ok, +0.0} = HistogramPercentile.query(:d, 0.0)
    assert {:ok, 100.0} = HistogramPercentile.query(:d, 1.0)
  end

  test "values are clamped into the edge buckets" do
    start_server([])

    HistogramPercentile.record(:c, -5)
    HistogramPercentile.record(:c, 200)

    assert {:ok, +0.0} = HistogramPercentile.query(:c, 0.0)
    assert {:ok, 100.0} = HistogramPercentile.query(:c, 1.0)
  end

  test "a below-range value lands in the first bucket rather than being dropped" do
    start_server([])

    HistogramPercentile.record(:lowc, -5)

    # A single sample clamped into bucket 0 -> the median sits mid-bucket.
    assert {:ok, p50} = HistogramPercentile.query(:lowc, 0.5)
    assert_in_delta p50, 5.0, 0.001
  end

  test "an above-range value lands in the last bucket rather than being dropped" do
    start_server([])

    HistogramPercentile.record(:hic, 500)

    assert {:ok, p50} = HistogramPercentile.query(:hic, 0.5)
    assert_in_delta p50, 95.0, 0.001
  end

  test "a value exactly on an interior edge belongs to the higher bucket" do
    start_server([])

    HistogramPercentile.record(:edge, 10)

    # Bucket 1 covers [10, 20), so the estimate is mid-bucket-1.
    assert {:ok, p50} = HistogramPercentile.query(:edge, 0.5)
    assert_in_delta p50, 15.0, 0.001
  end

  test "a value exactly on the top edge belongs to the closed last bucket" do
    start_server([])

    HistogramPercentile.record(:top, 100)

    assert {:ok, p50} = HistogramPercentile.query(:top, 0.5)
    assert_in_delta p50, 95.0, 0.001
  end

  test "interpolation weights the target against the counts of the chosen bucket" do
    start_server([])

    for _ <- 1..3, do: HistogramPercentile.record(:i, 5)
    HistogramPercentile.record(:i, 95)

    # n == 4; bucket 0 holds 3, bucket 9 holds 1.
    assert {:ok, p25} = HistogramPercentile.query(:i, 0.25)
    assert is_float(p25)
    # target 1.0 inside bucket 0 -> 0 + 10 * (1/3)
    assert_in_delta p25, 3.3333, 0.001

    assert {:ok, p50} = HistogramPercentile.query(:i, 0.50)
    # target 2.0 inside bucket 0 -> 0 + 10 * (2/3)
    assert_in_delta p50, 6.6667, 0.001

    assert {:ok, p90} = HistogramPercentile.query(:i, 0.90)
    # target 3.6 falls in bucket 9 with cum_before 3 -> 90 + 10 * 0.6
    assert_in_delta p90, 96.0, 0.001
  end

  # ---------------------------------------------------------
  # Empty / reset
  # ---------------------------------------------------------

  test "unknown series returns :empty" do
    start_server([])
    assert {:error, :empty} = HistogramPercentile.query(:nope, 0.5)
  end

  test "reset clears a series and it can be reused" do
    start_server([])

    for v <- 1..50, do: HistogramPercentile.record(:r, v)
    assert {:ok, _} = HistogramPercentile.query(:r, 0.5)

    assert :ok = HistogramPercentile.reset(:r)
    assert {:error, :empty} = HistogramPercentile.query(:r, 0.5)

    HistogramPercentile.record(:r, 55)
    assert {:ok, _} = HistogramPercentile.query(:r, 0.5)
  end

  # ---------------------------------------------------------
  # Time windowing across slices
  # ---------------------------------------------------------

  test "counts from multiple live slices are aggregated" do
    start_server([])

    for v <- 1..50, do: HistogramPercentile.record(:t, v)
    Clock.advance(100)
    for v <- 51..100, do: HistogramPercentile.record(:t, v)

    assert {:ok, p50} = HistogramPercentile.query(:t, 0.50)
    assert_in_delta p50, 51.0, 0.001
  end

  test "slices outside the window are excluded" do
    start_server([])

    for v <- 1..100, do: HistogramPercentile.record(:t, v)

    Clock.advance(999)
    assert {:ok, _} = HistogramPercentile.query(:t, 0.5)

    Clock.advance(1)
    assert {:error, :empty} = HistogramPercentile.query(:t, 0.5)
  end

  test "samples inside one slice accumulate into the same histogram" do
    # slice_ms = ceil(1000 / 4) = 250, so t = 0 and t = 4 share slice 0.
    start_server(window_ms: 1000, slots: 4)

    HistogramPercentile.record(:acc, 5)
    Clock.advance(4)
    HistogramPercentile.record(:acc, 95)

    # n == 2: target 1.0 exhausts bucket 0 exactly -> its high edge.
    assert {:ok, p50} = HistogramPercentile.query(:acc, 0.5)
    assert_in_delta p50, 10.0, 0.001
  end

  test "slice width is the window divided by slots, rounded up" do
    # slice_ms = ceil(1000 / 4) = 250, so a sample at t = 250 starts slice 250.
    start_server(window_ms: 1000, slots: 4)

    Clock.advance(250)
    HistogramPercentile.record(:sw, 95)

    Clock.advance(999)
    # now = 1249: 1249 - 250 = 999 < 1000, still live.
    assert {:ok, p50} = HistogramPercentile.query(:sw, 0.5)
    assert_in_delta p50, 95.0, 0.001

    Clock.advance(1)
    # now = 1250: 1250 - 250 = 1000, aged out.
    assert {:error, :empty} = HistogramPercentile.query(:sw, 0.5)
  end

  test "reusing a ring slot discards the previous cycle's counts" do
    # slice_ms = 250 with 4 slots, so slice 4 (t = 1000) reuses slot 0.
    start_server(window_ms: 1000, slots: 4)

    HistogramPercentile.record(:ring, 5)
    Clock.advance(1000)
    HistogramPercentile.record(:ring, 95)

    # Only the new sample survives; if the old counts lingered the median
    # would be pulled down to bucket 0's high edge (10.0).
    assert {:ok, p50} = HistogramPercentile.query(:ring, 0.5)
    assert_in_delta p50, 95.0, 0.001
  end

  test "the default slot count is 60" do
    # With window_ms = 61 the default 60 slots give slice_ms = ceil(61/60) = 2,
    # so a sample recorded at t = 1 belongs to the slice starting at 0.
    start_supervised!(
      {HistogramPercentile,
       clock: &Clock.now/0, edges: Enum.map(0..10, &(&1 * 10)), window_ms: 61}
    )

    Clock.advance(1)
    HistogramPercentile.record(:ds, 5)

    Clock.advance(59)
    # now = 60: 60 - 0 = 60 < 61, still live.
    assert {:ok, _} = HistogramPercentile.query(:ds, 0.5)

    Clock.advance(1)
    # now = 61: 61 - 0 = 61, the slice has aged out.
    assert {:error, :empty} = HistogramPercentile.query(:ds, 0.5)
  end

  test "aged-out slice is excluded while a newer live slice remains" do
    # TODO
  end

  # ---------------------------------------------------------
  # Independence & validation
  # ---------------------------------------------------------

  test "series are independent" do
    start_server([])

    for v <- 1..100, do: HistogramPercentile.record(:a, v)
    for _ <- 1..10, do: HistogramPercentile.record(:b, 5)

    assert {:ok, pa} = HistogramPercentile.query(:a, 0.5)
    assert_in_delta pa, 51.0, 0.001

    HistogramPercentile.reset(:a)
    assert {:error, :empty} = HistogramPercentile.query(:a, 0.5)
    assert {:ok, _} = HistogramPercentile.query(:b, 0.5)
  end

  test "invalid edges raise" do
    assert_raise ArgumentError, fn ->
      HistogramPercentile.start_link(
        name: :bad1,
        clock: &Clock.now/0,
        edges: [10, 5],
        window_ms: 1000
      )
    end
  end

  test "non-positive window_ms raises synchronously from start_link" do
    assert_raise ArgumentError, fn ->
      HistogramPercentile.start_link(
        name: :bad_window,
        clock: &Clock.now/0,
        edges: [0, 10, 20],
        window_ms: 0
      )
    end
  end

  test "edges with fewer than two entries raise" do
    assert_raise ArgumentError, fn ->
      HistogramPercentile.start_link(
        name: :bad_edges_len,
        clock: &Clock.now/0,
        edges: [10],
        window_ms: 1000
      )
    end
  end

  test "non-positive slots raises synchronously from start_link" do
    assert_raise ArgumentError, fn ->
      HistogramPercentile.start_link(
        name: :bad_slots,
        clock: &Clock.now/0,
        edges: [0, 10, 20],
        window_ms: 1000,
        slots: 0
      )
    end
  end
end
```

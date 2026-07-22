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

  test "aged-out slice is excluded while a newer live slice remains" do
    start_server([])

    for _ <- 1..10, do: HistogramPercentile.record(:w, 5)
    Clock.advance(500)
    for _ <- 1..10, do: HistogramPercentile.record(:w, 95)

    # now = 500: both slices live (a mix of low and high values).
    # Advance so the first slice (start 0) ages out while the second
    # (start 500) stays live; the first slot is never reused.
    Clock.advance(600)

    # now = 1100: 1100 - 0 >= 1000 (excluded), 1100 - 500 < 1000 (live).
    assert {:ok, p50} = HistogramPercentile.query(:w, 0.5)
    assert_in_delta p50, 95.0, 0.001
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

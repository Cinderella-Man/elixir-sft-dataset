defmodule RankPercentileTest do
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
    start_supervised!({RankPercentile, Keyword.put_new(opts, :clock, &Clock.now/0)})
    :ok
  end

  # ---------------------------------------------------------
  # Forward query (nearest-rank)
  # ---------------------------------------------------------

  test "forward percentile query matches nearest-rank" do
    start_server([])
    for v <- 1..100, do: assert :ok = RankPercentile.record(:d, v)

    assert {:ok, 50} = RankPercentile.query(:d, 0.50)
    assert {:ok, 95} = RankPercentile.query(:d, 0.95)
    assert {:ok, 1} = RankPercentile.query(:d, 0.0)
    assert {:ok, 100} = RankPercentile.query(:d, 1.0)
  end

  # ---------------------------------------------------------
  # Inverse query: rank / empirical CDF
  # ---------------------------------------------------------

  test "rank returns the fraction of samples at or below a value" do
    start_server([])
    for v <- 1..100, do: RankPercentile.record(:d, v)

    assert {:ok, 0.5} = RankPercentile.rank(:d, 50)
    assert {:ok, 0.01} = RankPercentile.rank(:d, 1)
    assert {:ok, 1.0} = RankPercentile.rank(:d, 100)
  end

  test "rank clamps below min and above max" do
    start_server([])
    for v <- 1..10, do: RankPercentile.record(:d, v)

    assert {:ok, 0.0} = RankPercentile.rank(:d, 0)
    assert {:ok, 1.0} = RankPercentile.rank(:d, 999)
  end

  test "rank on an empty series is :empty" do
    start_server([])
    assert {:error, :empty} = RankPercentile.rank(:nope, 5)
  end

  # ---------------------------------------------------------
  # count_above (SLA violations)
  # ---------------------------------------------------------

  test "count_above counts samples strictly greater than the threshold" do
    start_server([])
    for v <- 1..100, do: RankPercentile.record(:d, v)

    assert {:ok, 5} = RankPercentile.count_above(:d, 95)
    assert {:ok, 100} = RankPercentile.count_above(:d, 0)
    assert {:ok, 0} = RankPercentile.count_above(:d, 100)
  end

  test "count_above on an empty series returns zero" do
    start_server([])
    assert {:ok, 0} = RankPercentile.count_above(:nope, 5)
  end

  # ---------------------------------------------------------
  # Windowing applies to every query direction
  # ---------------------------------------------------------

  test "expired samples drop out of query, rank, and count_above" do
    start_server(window_ms: 1_000)

    for v <- 1..50, do: RankPercentile.record(:t, v)

    Clock.advance(1_000)

    for v <- 60..69, do: RankPercentile.record(:t, v)

    # only [60..69] are live now
    assert {:ok, 64} = RankPercentile.query(:t, 0.50)
    assert {:ok, 0.5} = RankPercentile.rank(:t, 64)
    assert {:ok, 5} = RankPercentile.count_above(:t, 64)
  end

  test "count-based window keeps only the most recent samples" do
    start_server(max_samples: 5)
    for v <- 1..10, do: RankPercentile.record(:c, v)

    # only [6,7,8,9,10] remain
    assert {:ok, 6} = RankPercentile.query(:c, 0.0)
    assert {:ok, 0.2} = RankPercentile.rank(:c, 6)
    assert {:ok, 2} = RankPercentile.count_above(:c, 8)
  end

  # ---------------------------------------------------------
  # Reset & independence
  # ---------------------------------------------------------

  test "reset clears a series" do
    start_server([])
    for v <- 1..10, do: RankPercentile.record(:r, v)
    assert :ok = RankPercentile.reset(:r)
    assert {:error, :empty} = RankPercentile.query(:r, 0.5)
    assert {:ok, 0} = RankPercentile.count_above(:r, 0)
  end

  test "series are independent" do
    start_server([])
    for v <- 1..100, do: RankPercentile.record(:a, v)
    for v <- 200..209, do: RankPercentile.record(:b, v)

    assert {:ok, 0.5} = RankPercentile.rank(:a, 50)
    assert {:ok, 0.0} = RankPercentile.rank(:b, 100)
    assert {:ok, 10} = RankPercentile.count_above(:b, 100)
  end
end
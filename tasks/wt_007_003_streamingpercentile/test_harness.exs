defmodule StreamingPercentileTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = StreamingPercentile.start_link([])
    %{sp: pid}
  end

  defp close_to(a, b, eps \\ 1.0e-9), do: abs(a - b) <= eps

  # -------------------------------------------------------
  # No-data behavior
  # -------------------------------------------------------

  test "percentile on empty stream returns :no_data", %{sp: s} do
    assert {:error, :no_data} = StreamingPercentile.percentile(s, "x", 0.5)
    assert {:error, :no_data} = StreamingPercentile.percentiles(s, "x", [0.5, 0.95])
    assert {:error, :no_data} = StreamingPercentile.window(s, "x")
  end

  # -------------------------------------------------------
  # Validation
  # -------------------------------------------------------

  test "percentile rejects out-of-range q", %{sp: s} do
    StreamingPercentile.push(s, "a", 10, 5)

    assert {:error, :invalid_quantile} = StreamingPercentile.percentile(s, "a", -0.1)
    assert {:error, :invalid_quantile} = StreamingPercentile.percentile(s, "a", 1.1)
  end

  test "percentiles rejects if any q is out of range", %{sp: s} do
    StreamingPercentile.push(s, "a", 10, 5)

    assert {:error, :invalid_quantile} =
             StreamingPercentile.percentiles(s, "a", [0.5, 2.0])
  end

  test "push rejects non-numeric values and non-positive window sizes", %{sp: s} do
    assert_raise FunctionClauseError, fn ->
      StreamingPercentile.push(s, "a", :not_number, 10)
    end

    assert_raise FunctionClauseError, fn ->
      StreamingPercentile.push(s, "a", 10, 0)
    end

    assert_raise FunctionClauseError, fn ->
      StreamingPercentile.push(s, "a", 10, -1)
    end
  end

  # -------------------------------------------------------
  # Basic quantile math
  # -------------------------------------------------------

  test "single-value window returns that value for any q", %{sp: s} do
    StreamingPercentile.push(s, "a", 42, 10)

    for q <- [0.0, 0.25, 0.5, 0.75, 1.0] do
      {:ok, v} = StreamingPercentile.percentile(s, "a", q)
      assert v == 42.0
    end
  end

  test "q=0 and q=1 return min and max", %{sp: s} do
    for v <- [10, 30, 20, 50, 40], do: StreamingPercentile.push(s, "a", v, 5)

    {:ok, min} = StreamingPercentile.percentile(s, "a", 0.0)
    {:ok, max} = StreamingPercentile.percentile(s, "a", 1.0)

    assert min == 10.0
    assert max == 50.0
  end

  test "median of odd-length sorted stream is the middle element", %{sp: s} do
    for v <- [10, 20, 30, 40, 50], do: StreamingPercentile.push(s, "a", v, 5)

    {:ok, med} = StreamingPercentile.percentile(s, "a", 0.5)
    assert med == 30.0
  end

  test "median of even-length stream linearly interpolates", %{sp: s} do
    for v <- [10, 20, 30, 40], do: StreamingPercentile.push(s, "a", v, 4)

    # sorted = [10, 20, 30, 40], N=4, rank = 0.5 * 3 = 1.5
    # lo=1, hi=2, frac=0.5, result = 20 + 0.5*(30-20) = 25
    {:ok, med} = StreamingPercentile.percentile(s, "a", 0.5)
    assert close_to(med, 25.0)
  end

  test "percentile between ranks uses linear interpolation", %{sp: s} do
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 10)

    # sorted = 1..10 (N=10). rank = 0.25 * 9 = 2.25
    # lo=2, hi=3, sorted[2]=3, sorted[3]=4, frac=0.25
    # result = 3 + 0.25 * (4 - 3) = 3.25
    {:ok, p25} = StreamingPercentile.percentile(s, "a", 0.25)
    assert close_to(p25, 3.25)

    # p95: rank = 0.95 * 9 = 8.55
    # lo=8, hi=9, sorted[8]=9, sorted[9]=10, frac=0.55
    # result = 9 + 0.55*(10-9) = 9.55
    {:ok, p95} = StreamingPercentile.percentile(s, "a", 0.95)
    assert close_to(p95, 9.55)
  end

  # -------------------------------------------------------
  # Batch query
  # -------------------------------------------------------

  test "percentiles/3 returns a map of q -> value", %{sp: s} do
    for v <- 1..100, do: StreamingPercentile.push(s, "a", v, 100)

    {:ok, results} = StreamingPercentile.percentiles(s, "a", [0.5, 0.95, 0.99])

    # With 100 values (1..100), N=100, rank(q) = q * 99.
    # p50: rank 49.5 → sorted[49]=50, sorted[50]=51, frac=0.5 → 50.5
    # p95: rank 94.05 → sorted[94]=95, sorted[95]=96, frac=0.05 → 95.05
    # p99: rank 98.01 → sorted[98]=99, sorted[99]=100, frac=0.01 → 99.01
    assert close_to(results[0.5], 50.5)
    assert close_to(results[0.95], 95.05)
    assert close_to(results[0.99], 99.01)
  end

  test "percentiles/3 on a single-value window returns same value for every q", %{sp: s} do
    StreamingPercentile.push(s, "a", 7.5, 3)

    {:ok, results} = StreamingPercentile.percentiles(s, "a", [0.0, 0.5, 0.99])

    for q <- [0.0, 0.5, 0.99], do: assert(results[q] == 7.5)
  end

  # -------------------------------------------------------
  # Sliding window behavior
  # -------------------------------------------------------

  test "window bounded to window_size — oldest values drop off", %{sp: s} do
    # Fill with 10 values at window=5 — only last 5 should remain
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 5)

    {:ok, current} = StreamingPercentile.window(s, "a")
    assert current == [6.0, 7.0, 8.0, 9.0, 10.0]
  end

  test "quantile is computed over current window only, not full history", %{sp: s} do
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 3)

    {:ok, current} = StreamingPercentile.window(s, "a")
    assert current == [8.0, 9.0, 10.0]

    {:ok, med} = StreamingPercentile.percentile(s, "a", 0.5)
    assert med == 9.0
  end

  # -------------------------------------------------------
  # window_size growth (max_window_size semantics)
  # -------------------------------------------------------

  test "window_size grows with largest-ever request and never shrinks", %{sp: s} do
    # Push with window=3
    for v <- 1..5, do: StreamingPercentile.push(s, "a", v, 3)

    {:ok, w1} = StreamingPercentile.window(s, "a")
    assert length(w1) == 3

    # Push with window=10 — max_window_size grows
    for v <- 6..10, do: StreamingPercentile.push(s, "a", v, 10)

    {:ok, w2} = StreamingPercentile.window(s, "a")
    # We retained 3 then grew to 10 and pushed 5 more → length 8
    assert length(w2) == 8

    # Push with window=2 (smaller) — max_window_size does NOT shrink
    StreamingPercentile.push(s, "a", 11, 2)
    {:ok, w3} = StreamingPercentile.window(s, "a")
    # max remained 10, so length caps at 10 as we add more
    assert length(w3) == 9

    state = :sys.get_state(s)
    assert state.streams["a"].max_window_size == 10
  end

  # -------------------------------------------------------
  # Stream independence
  # -------------------------------------------------------

  test "different stream names are independent", %{sp: s} do
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 10)
    for v <- 100..110, do: StreamingPercentile.push(s, "b", v, 11)

    {:ok, a_med} = StreamingPercentile.percentile(s, "a", 0.5)
    {:ok, b_med} = StreamingPercentile.percentile(s, "b", 0.5)

    assert close_to(a_med, 5.5)
    assert close_to(b_med, 105.0)

    # Pushing to "a" doesn't affect "b"
    StreamingPercentile.push(s, "a", 99999, 10)
    {:ok, b_med_again} = StreamingPercentile.percentile(s, "b", 0.5)
    assert close_to(b_med, b_med_again)
  end

  # -------------------------------------------------------
  # Duplicate values
  # -------------------------------------------------------

  test "quantiles handle duplicate values correctly", %{sp: s} do
    for _ <- 1..10, do: StreamingPercentile.push(s, "a", 7.0, 10)

    for q <- [0.0, 0.25, 0.5, 0.75, 0.95, 1.0] do
      {:ok, v} = StreamingPercentile.percentile(s, "a", q)
      assert v == 7.0
    end
  end
end

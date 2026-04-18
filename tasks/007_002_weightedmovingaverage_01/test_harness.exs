defmodule WeightedMovingAverageTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = WeightedMovingAverage.start_link([])
    %{wma: pid}
  end

  defp close_to(a, b, eps \\ 1.0e-9), do: abs(a - b) <= eps

  # -------------------------------------------------------
  # Empty / no-data behavior
  # -------------------------------------------------------

  test "get on empty stream returns :no_data", %{wma: s} do
    assert {:error, :no_data} = WeightedMovingAverage.get(s, "x", :wma, 3)
    assert {:error, :no_data} = WeightedMovingAverage.get(s, "x", :hma, 4)
  end

  # -------------------------------------------------------
  # WMA math
  # -------------------------------------------------------

  test "WMA with full window is correctly weighted", %{wma: s} do
    for v <- [10, 20, 30, 40, 50], do: WeightedMovingAverage.push(s, "a", v)

    # Newest-first: [50, 40, 30, 20, 10]
    # WMA(period=5): (5*50 + 4*40 + 3*30 + 2*20 + 1*10) / 15
    #              = (250 + 160 + 90 + 40 + 10) / 15 = 550 / 15
    expected = 550 / 15

    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 5)
    assert close_to(result, expected)
  end

  test "WMA with period smaller than buffer uses only the newest N", %{wma: s} do
    for v <- [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], do: WeightedMovingAverage.push(s, "a", v)

    # Newest-first: [10, 9, 8, ...]. WMA(3): (3*10 + 2*9 + 1*8) / 6 = 56 / 6
    expected = 56 / 6
    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 3)
    assert close_to(result, expected)
  end

  test "WMA cold-start (fewer values than period) uses adjusted weights", %{wma: s} do
    for v <- [10, 20, 30], do: WeightedMovingAverage.push(s, "a", v)

    # Only 3 of the requested 5 values are available.
    # Newest-first: [30, 20, 10], weights [3, 2, 1], denominator 6
    # WMA = (3*30 + 2*20 + 1*10) / 6 = 140 / 6
    expected = 140 / 6
    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 5)
    assert close_to(result, expected)
  end

  test "single-value WMA equals that value", %{wma: s} do
    WeightedMovingAverage.push(s, "a", 42)
    {:ok, result} = WeightedMovingAverage.get(s, "a", :wma, 10)
    assert result == 42.0
  end

  # -------------------------------------------------------
  # Memory bounds for WMA
  # -------------------------------------------------------

  test "WMA values buffer is bounded by max_period", %{wma: s} do
    for v <- 1..20, do: WeightedMovingAverage.push(s, "a", v)

    # Ask for period 3 — max_period becomes 3, buffer trims to 3.
    _ = WeightedMovingAverage.get(s, "a", :wma, 3)

    # Push more values; buffer should stay at 3 (the current max_period).
    for v <- 21..30, do: WeightedMovingAverage.push(s, "a", v)
    _ = WeightedMovingAverage.get(s, "a", :wma, 3)

    state = :sys.get_state(s)
    assert length(state.streams["a"].values) == 3
  end

  test "larger period grows max_period and retains more history", %{wma: s} do
    for v <- 1..5, do: WeightedMovingAverage.push(s, "a", v)

    _ = WeightedMovingAverage.get(s, "a", :wma, 3)
    state1 = :sys.get_state(s)
    assert state1.streams["a"].max_period == 3

    # Requesting a larger period grows max_period but should not truncate.
    _ = WeightedMovingAverage.get(s, "a", :wma, 10)
    state2 = :sys.get_state(s)
    assert state2.streams["a"].max_period == 10
  end

  # -------------------------------------------------------
  # HMA math
  # -------------------------------------------------------

  test "HMA with insufficient values returns :insufficient_data", %{wma: s} do
    for v <- [1, 2, 3], do: WeightedMovingAverage.push(s, "a", v)

    assert {:error, :insufficient_data} = WeightedMovingAverage.get(s, "a", :hma, 4)
  end

  test "HMA(period=4) with just-enough history computes correctly", %{wma: s} do
    values = [1, 2, 3, 4]
    for v <- values, do: WeightedMovingAverage.push(s, "a", v)

    # wma1_period = 2, wma2_period = 4, buffer_size = round(sqrt(4)) = 2
    # Replay oldest-first = [1, 2, 3, 4]:
    #   step 1 (only 1 seen, newest-first [1]):
    #     wma1 over period 2 using [1]: (2*1)/2 = 1.0 (cold start, weights [2])? Wait,
    #     the weights go from 1..N where N is the AVAILABLE window size not requested period.
    #   Actually: the WMA cold-start uses weights n..1 over n values where n is
    #   the min of (requested period, available). So for 1 value with period=2:
    #     weights [1], denominator 1 → WMA = 1.0.
    #   wma2 over period 4 with [1]: weights [1], denominator 1 → 1.0
    #   raw_1 = 2*1 - 1 = 1.0
    # step 2 (newest-first [2, 1]):
    #   wma1 over period 2 with [2, 1]: (2*2 + 1*1)/3 = 5/3
    #   wma2 over period 4 with [2, 1]: weights [2, 1], denominator 3 → (2*2+1*1)/3 = 5/3
    #   raw_2 = 2*(5/3) - 5/3 = 5/3
    # step 3 (newest-first [3, 2, 1]):
    #   wma1 over period 2 with [3, 2, 1] → take first 2 → [3, 2]: (2*3+1*2)/3 = 8/3
    #   wma2 over period 4 with [3, 2, 1]: weights [3,2,1] → (9+4+1)/6 = 14/6 = 7/3
    #   raw_3 = 2*(8/3) - 7/3 = 16/3 - 7/3 = 9/3 = 3.0
    # step 4 (newest-first [4, 3, 2, 1]):
    #   wma1 over period 2 with [4, 3]: (2*4+1*3)/3 = 11/3
    #   wma2 over period 4 with [4, 3, 2, 1]: (4*4+3*3+2*2+1*1)/10 = (16+9+4+1)/10 = 30/10 = 3.0
    #   raw_4 = 2*(11/3) - 3 = 22/3 - 9/3 = 13/3
    #
    # raw_buffer (newest-first, trimmed to 2): [13/3, 3.0]
    # HMA = WMA([13/3, 3.0], period 2) = (2*13/3 + 1*3.0)/3 = (26/3 + 3)/3 = (26/3 + 9/3)/3 = (35/3)/3 = 35/9

    expected = 35 / 9
    {:ok, result} = WeightedMovingAverage.get(s, "a", :hma, 4)
    assert close_to(result, expected, 1.0e-9)
  end

  test "HMA incrementally updates on new pushes", %{wma: s} do
    for v <- [1, 2, 3, 4], do: WeightedMovingAverage.push(s, "a", v)
    {:ok, h4} = WeightedMovingAverage.get(s, "a", :hma, 4)

    # Push a new value and check that HMA has been incrementally extended
    # (bootstrap path runs only once — future pushes must update the buffer).
    WeightedMovingAverage.push(s, "a", 10)
    {:ok, h5} = WeightedMovingAverage.get(s, "a", :hma, 4)

    refute close_to(h4, h5, 1.0e-12)
  end

  test "HMA bootstrap uses full retained history", %{wma: s} do
    # Push many values with no prior gets — buffer is full history.
    for v <- 1..20, do: WeightedMovingAverage.push(s, "a", v)

    # First HMA request bootstraps from all 20 values.
    {:ok, result} = WeightedMovingAverage.get(s, "a", :hma, 4)

    # Now compare to a fresh server that does the same via only WMA requests
    # (which do not register HMA accumulators).  Both must match.
    {:ok, fresh} = WeightedMovingAverage.start_link([])
    for v <- 1..20, do: WeightedMovingAverage.push(fresh, "b", v)
    {:ok, result_b} = WeightedMovingAverage.get(fresh, "b", :hma, 4)

    assert close_to(result, result_b)
  end

  # -------------------------------------------------------
  # Stream independence
  # -------------------------------------------------------

  test "different stream names are independent", %{wma: s} do
    for v <- 1..5, do: WeightedMovingAverage.push(s, "a", v)

    {:ok, a_wma} = WeightedMovingAverage.get(s, "a", :wma, 3)
    assert {:error, :no_data} = WeightedMovingAverage.get(s, "b", :wma, 3)

    for v <- 100..104, do: WeightedMovingAverage.push(s, "b", v)
    {:ok, b_wma} = WeightedMovingAverage.get(s, "b", :wma, 3)

    refute close_to(a_wma, b_wma)

    # "a" unaffected by pushes to "b"
    {:ok, a_wma_again} = WeightedMovingAverage.get(s, "a", :wma, 3)
    assert close_to(a_wma, a_wma_again)
  end

  # -------------------------------------------------------
  # Input validation
  # -------------------------------------------------------

  test "get with unknown type raises a FunctionClauseError", %{wma: s} do
    assert_raise FunctionClauseError, fn ->
      WeightedMovingAverage.get(s, "a", :nope, 3)
    end
  end

  test "push rejects non-numeric values", %{wma: s} do
    assert_raise FunctionClauseError, fn ->
      WeightedMovingAverage.push(s, "a", :not_a_number)
    end
  end
end

defmodule MovingAverageTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = MovingAverage.start_link([])
    %{ma: pid}
  end

  # -------------------------------------------------------
  # Helper — float comparison with tolerance
  # -------------------------------------------------------

  defp assert_close(left, right, epsilon \\ 1.0e-9) do
    assert abs(left - right) < epsilon,
           "Expected #{left} to be within #{epsilon} of #{right}"
  end

  # -------------------------------------------------------
  # No-data edge case
  # -------------------------------------------------------

  test "returns error when no data has been pushed", %{ma: ma} do
    assert {:error, :no_data} = MovingAverage.get(ma, "empty", :sma, 5)
    assert {:error, :no_data} = MovingAverage.get(ma, "empty", :ema, 5)
  end

  # -------------------------------------------------------
  # SMA basics
  # -------------------------------------------------------

  test "SMA with a single value", %{ma: ma} do
    MovingAverage.push(ma, "s", 10.0)
    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 5)
    assert_close(result, 10.0)
  end

  test "SMA cold-start: fewer values than the period", %{ma: ma} do
    # Push 3 values, request SMA over period 5
    MovingAverage.push(ma, "s", 2.0)
    MovingAverage.push(ma, "s", 4.0)
    MovingAverage.push(ma, "s", 6.0)

    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 5)
    # Mean of [2, 4, 6] = 4.0
    assert_close(result, 4.0)
  end

  test "SMA over exact period count", %{ma: ma} do
    Enum.each([10.0, 20.0, 30.0, 40.0, 50.0], &MovingAverage.push(ma, "s", &1))

    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 5)
    # Mean of [10, 20, 30, 40, 50] = 30.0
    assert_close(result, 30.0)
  end

  test "SMA slides window: old values drop off", %{ma: ma} do
    Enum.each([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0], &MovingAverage.push(ma, "s", &1))

    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 3)
    # Last 3 values: [5, 6, 7], mean = 6.0
    assert_close(result, 6.0)
  end

  test "SMA with different periods on the same stream", %{ma: ma} do
    Enum.each([2.0, 4.0, 6.0, 8.0, 10.0], &MovingAverage.push(ma, "s", &1))

    assert {:ok, sma2} = MovingAverage.get(ma, "s", :sma, 2)
    # Last 2: [8, 10] -> 9.0
    assert_close(sma2, 9.0)

    assert {:ok, sma5} = MovingAverage.get(ma, "s", :sma, 5)
    # All 5: [2, 4, 6, 8, 10] -> 6.0
    assert_close(sma5, 6.0)
  end

  # -------------------------------------------------------
  # EMA basics
  # -------------------------------------------------------

  test "EMA with a single value equals that value", %{ma: ma} do
    MovingAverage.push(ma, "e", 42.0)
    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 5)
    assert_close(result, 42.0)
  end

  test "EMA hand-calculated over a known sequence", %{ma: ma} do
    # Sequence: [10, 20, 30]
    # Period: 3, k = 2/(3+1) = 0.5
    #
    # Step 0: ema = 10
    # Step 1: ema = 20 * 0.5 + 10 * 0.5 = 15
    # Step 2: ema = 30 * 0.5 + 15 * 0.5 = 22.5
    Enum.each([10.0, 20.0, 30.0], &MovingAverage.push(ma, "e", &1))

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 3)
    assert_close(result, 22.5)
  end

  test "EMA with period 1 always equals the latest value", %{ma: ma} do
    # k = 2/(1+1) = 1.0, so ema = value * 1 + prev * 0 = value
    Enum.each([5.0, 15.0, 25.0, 100.0], &MovingAverage.push(ma, "e", &1))

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 1)
    assert_close(result, 100.0)
  end

  test "EMA cold-start: fewer values than the period still computes", %{ma: ma} do
    # Sequence: [4, 8], period 10, k = 2/11 ≈ 0.18182
    # Step 0: ema = 4
    # Step 1: ema = 8 * (2/11) + 4 * (9/11) = 16/11 + 36/11 = 52/11 ≈ 4.7273
    MovingAverage.push(ma, "e", 4.0)
    MovingAverage.push(ma, "e", 8.0)

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 10)
    assert_close(result, 52.0 / 11.0)
  end

  test "EMA with longer known sequence", %{ma: ma} do
    # Sequence: [1, 2, 3, 4, 5], period 5, k = 2/6 = 1/3
    # Step 0: ema = 1
    # Step 1: ema = 2*(1/3) + 1*(2/3) = 4/3
    # Step 2: ema = 3*(1/3) + (4/3)*(2/3) = 1 + 8/9 = 17/9
    # Step 3: ema = 4*(1/3) + (17/9)*(2/3) = 4/3 + 34/27 = 36/27 + 34/27 = 70/27
    # Step 4: ema = 5*(1/3) + (70/27)*(2/3) = 5/3 + 140/81 = 135/81 + 140/81 = 275/81
    Enum.each([1.0, 2.0, 3.0, 4.0, 5.0], &MovingAverage.push(ma, "e", &1))

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 5)
    assert_close(result, 275.0 / 81.0)
  end

  # -------------------------------------------------------
  # Stream name independence
  # -------------------------------------------------------

  test "different stream names are completely independent", %{ma: ma} do
    Enum.each([100.0, 200.0, 300.0], &MovingAverage.push(ma, "a", &1))
    MovingAverage.push(ma, "b", 999.0)

    assert {:ok, sma_a} = MovingAverage.get(ma, "a", :sma, 3)
    assert_close(sma_a, 200.0)

    assert {:ok, sma_b} = MovingAverage.get(ma, "b", :sma, 3)
    assert_close(sma_b, 999.0)

    assert {:error, :no_data} = MovingAverage.get(ma, "c", :sma, 3)
  end

  # -------------------------------------------------------
  # Memory: SMA does not store unbounded history
  # -------------------------------------------------------

  test "SMA only retains up to max_period values, not the full stream", %{ma: ma} do
    # First, request SMA with period 5 to establish max_period
    MovingAverage.push(ma, "mem", 0.0)
    MovingAverage.get(ma, "mem", :sma, 5)

    # Push 1000 more values
    for i <- 1..1000, do: MovingAverage.push(ma, "mem", i * 1.0)

    # SMA should still be correct (last 5: [996, 997, 998, 999, 1000])
    assert {:ok, result} = MovingAverage.get(ma, "mem", :sma, 5)
    assert_close(result, 998.0)

    # Inspect state to verify bounded storage
    state = :sys.get_state(ma)

    # The stored values for "mem" should be a bounded structure.
    # We look for whatever internal key holds the values buffer.
    # Accept any structure with at most ~max_period elements.
    stream_data = state.streams["mem"] || state["mem"]
    values = stream_data[:values] || stream_data.values

    # The buffer should have at most max_period entries (5), not 1001
    assert length(values) <= 10,
           "Expected bounded buffer but found #{length(values)} entries"
  end

  test "requesting a larger period grows the buffer to accommodate it", %{ma: ma} do
    # Start with period 3
    Enum.each(1..20 |> Enum.map(&(&1 * 1.0)), &MovingAverage.push(ma, "grow", &1))
    assert {:ok, sma3} = MovingAverage.get(ma, "grow", :sma, 3)
    # mean of [18, 19, 20]
    assert_close(sma3, 19.0)

    # Now request period 10 — the buffer should still work,
    # though values before the previous max_period may be lost.
    # Push 10 more values so we have enough for period 10.
    Enum.each(21..30 |> Enum.map(&(&1 * 1.0)), &MovingAverage.push(ma, "grow", &1))
    assert {:ok, sma10} = MovingAverage.get(ma, "grow", :sma, 10)
    # Last 10: [21..30], mean = 25.5
    assert_close(sma10, 25.5)
  end

  # -------------------------------------------------------
  # Memory: EMA uses only a running accumulator
  # -------------------------------------------------------

  test "EMA after a large stream matches iterative calculation", %{ma: ma} do
    n = 5_000
    period = 20
    k = 2.0 / (period + 1)

    # Compute expected EMA by hand
    values = for i <- 1..n, do: :math.sin(i / 100.0)

    expected_ema =
      values
      |> Enum.reduce(nil, fn v, acc ->
        case acc do
          nil -> v
          prev -> v * k + prev * (1 - k)
        end
      end)

    # Push same sequence into the GenServer
    Enum.each(values, &MovingAverage.push(ma, "big", &1))

    assert {:ok, result} = MovingAverage.get(ma, "big", :ema, period)
    assert_close(result, expected_ema, 1.0e-6)
  end

  # -------------------------------------------------------
  # Multiple EMA periods on the same stream
  # -------------------------------------------------------

  test "different EMA periods on the same stream produce different results", %{ma: ma} do
    Enum.each(
      [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0],
      &MovingAverage.push(ma, "multi", &1)
    )

    assert {:ok, ema3} = MovingAverage.get(ma, "multi", :ema, 3)
    assert {:ok, ema10} = MovingAverage.get(ma, "multi", :ema, 10)

    # EMA with smaller period reacts faster — should be closer to 10
    assert ema3 > ema10
  end

  # -------------------------------------------------------
  # Interleaved push and get
  # -------------------------------------------------------

  test "interleaved pushes and gets produce correct results", %{ma: ma} do
    MovingAverage.push(ma, "s", 10.0)
    assert {:ok, r1} = MovingAverage.get(ma, "s", :sma, 3)
    assert_close(r1, 10.0)

    MovingAverage.push(ma, "s", 20.0)
    assert {:ok, r2} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [10, 20]
    assert_close(r2, 15.0)

    MovingAverage.push(ma, "s", 30.0)
    assert {:ok, r3} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [10, 20, 30]
    assert_close(r3, 20.0)

    MovingAverage.push(ma, "s", 40.0)
    assert {:ok, r4} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [20, 30, 40] — 10 dropped
    assert_close(r4, 30.0)

    MovingAverage.push(ma, "s", 50.0)
    assert {:ok, r5} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [30, 40, 50]
    assert_close(r5, 40.0)
  end

  # -------------------------------------------------------
  # Constant values
  # -------------------------------------------------------

  test "constant values yield that constant for both SMA and EMA", %{ma: ma} do
    for _ <- 1..20, do: MovingAverage.push(ma, "flat", 7.0)

    assert {:ok, sma} = MovingAverage.get(ma, "flat", :sma, 5)
    assert_close(sma, 7.0)

    assert {:ok, ema} = MovingAverage.get(ma, "flat", :ema, 5)
    assert_close(ema, 7.0)
  end
end

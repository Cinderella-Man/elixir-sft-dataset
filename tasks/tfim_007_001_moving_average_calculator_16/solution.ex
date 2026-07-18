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
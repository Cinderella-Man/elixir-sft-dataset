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
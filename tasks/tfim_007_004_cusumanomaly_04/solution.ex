  test "Welford mean matches the arithmetic mean over pushed values" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 1000, threshold: 1000.0)

    values = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
    for v <- values, do: CusumAnomaly.push(c, "s", v)

    {:ok, info} = CusumAnomaly.check(c, "s")
    expected_mean = Enum.sum(values) / length(values)
    assert close_to(info.mean, expected_mean)

    # Population stddev of the classic Welford test input is 2.0.
    assert close_to(info.stddev, 2.0, 1.0e-9)
  end
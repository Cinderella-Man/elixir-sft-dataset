  test "below-slack stddev skips CUSUM and returns :ok despite a large spike" do
    {:ok, c} = CusumAnomaly.start_link(warmup_samples: 3, threshold: 3.0, slack: 0.5)

    for _ <- 1..3, do: assert(:warming_up = CusumAnomaly.push(c, "s", 5.0))

    # stddev before this push is 0.0 (a flat signal), which is below slack,
    # so even a huge deviation must be absorbed with a plain :ok — no alert.
    assert :ok = CusumAnomaly.push(c, "s", 100.0)
  end
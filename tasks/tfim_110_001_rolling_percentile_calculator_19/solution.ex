  test "both windows constrain the same series simultaneously" do
    start_server(window_ms: 1_000, max_samples: 3)

    # t=0: four samples arrive, count window drops 10 -> live [20, 30, 40]
    for v <- [10, 20, 30, 40], do: Percentile.record(:both, v)
    assert {:ok, 20} = Percentile.query(:both, 0.0)
    assert {:ok, 40} = Percentile.query(:both, 1.0)

    # t=600: 50 arrives, count window drops the oldest -> live [30, 40, 50]
    Clock.advance(600)
    Percentile.record(:both, 50)
    assert {:ok, 30} = Percentile.query(:both, 0.0)
    assert {:ok, 50} = Percentile.query(:both, 1.0)

    # t=1100: the t=0 samples (30, 40) are 1100ms old and expire; 50 (age 600)
    # is the only live sample, so it is both the min and the max.
    Clock.advance(500)
    assert {:ok, 50} = Percentile.query(:both, 0.0)
    assert {:ok, 50} = Percentile.query(:both, 0.50)
    assert {:ok, 50} = Percentile.query(:both, 1.0)
  end
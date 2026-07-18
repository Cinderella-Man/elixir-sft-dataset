  test "time expiry still applies when a count window is also configured" do
    start_server(window_ms: 1_000, max_samples: 100)

    # Far fewer samples than max_samples, so only the time window can remove
    # them; once they age past the window the series must report empty.
    for v <- 1..3, do: Percentile.record(:both, v)
    assert {:ok, 1} = Percentile.query(:both, 0.0)
    assert {:ok, 3} = Percentile.query(:both, 1.0)

    Clock.advance(1_000)
    assert {:error, :empty} = Percentile.query(:both, 0.5)
  end
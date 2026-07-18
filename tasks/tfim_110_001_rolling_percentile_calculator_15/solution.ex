  test "expired samples do not contribute to the percentile rank" do
    start_server(window_ms: 1_000)

    # Record 1..50 at t=0
    for v <- 1..50, do: Percentile.record(:t, v)

    # t=1000: all of the above are expired
    Clock.advance(1_000)

    # Record 60..69 at t=1000
    for v <- 60..69, do: Percentile.record(:t, v)

    # Only the 10 fresh samples [60..69] count now
    assert {:ok, 60} = Percentile.query(:t, 0.0)
    assert {:ok, 69} = Percentile.query(:t, 1.0)
    # ceil(0.5*10) = 5 -> s_5 = 64
    assert {:ok, 64} = Percentile.query(:t, 0.50)
  end
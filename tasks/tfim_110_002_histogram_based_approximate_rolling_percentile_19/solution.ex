  test "aged-out slice is excluded while a newer live slice remains" do
    start_server([])

    for _ <- 1..10, do: HistogramPercentile.record(:w, 5)
    Clock.advance(500)
    for _ <- 1..10, do: HistogramPercentile.record(:w, 95)

    # now = 500: both slices live (a mix of low and high values).
    # Advance so the first slice (start 0) ages out while the second
    # (start 500) stays live; the first slot is never reused.
    Clock.advance(600)

    # now = 1100: 1100 - 0 >= 1000 (excluded), 1100 - 500 < 1000 (live).
    assert {:ok, p50} = HistogramPercentile.query(:w, 0.5)
    assert_in_delta p50, 95.0, 0.001
  end
  test "the default slot count is 60" do
    # With window_ms = 61 the default 60 slots give slice_ms = ceil(61/60) = 2,
    # so a sample recorded at t = 1 belongs to the slice starting at 0.
    start_supervised!(
      {HistogramPercentile,
       clock: &Clock.now/0, edges: Enum.map(0..10, &(&1 * 10)), window_ms: 61}
    )

    Clock.advance(1)
    HistogramPercentile.record(:ds, 5)

    Clock.advance(59)
    # now = 60: 60 - 0 = 60 < 61, still live.
    assert {:ok, _} = HistogramPercentile.query(:ds, 0.5)

    Clock.advance(1)
    # now = 61: 61 - 0 = 61, the slice has aged out.
    assert {:error, :empty} = HistogramPercentile.query(:ds, 0.5)
  end
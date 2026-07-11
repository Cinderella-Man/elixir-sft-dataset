  test "uniform aging does not change the reported percentile" do
    start_server([])

    DecayPercentile.record(:t, 1)
    DecayPercentile.record(:t, 100)

    # both fresh: nearest-rank median (lower of two) is 1
    assert {:ok, 1} = DecayPercentile.query(:t, 0.50)

    # advance the clock with no new records: both weights scale equally
    Clock.advance(3_000)
    assert {:ok, 1} = DecayPercentile.query(:t, 0.50)
  end
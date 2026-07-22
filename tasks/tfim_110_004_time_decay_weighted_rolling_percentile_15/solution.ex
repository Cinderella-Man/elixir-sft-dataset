  test "extremes stay correct in the small-but-nonzero weight regime" do
    start_server([])

    DecayPercentile.record(:tiny, 1)
    DecayPercentile.record(:tiny, 100)

    # 33 half-lives: each weight is ~1.16e-10 — far below any absolute float
    # tolerance, yet NOT underflowed. Uniform aging is neutral, so the
    # extremes must answer exactly as they did when fresh.
    Clock.advance(33_000)

    assert {:ok, 1} = DecayPercentile.query(:tiny, 0.0)
    assert {:ok, 100} = DecayPercentile.query(:tiny, 1.0)
    assert {:ok, 100} = DecayPercentile.query(:tiny, 0.75)
  end
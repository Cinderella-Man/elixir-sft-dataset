  test "time-based window keeps live samples and expires old ones" do
    start_server(window_ms: 1_000)

    # t=0
    Percentile.record(:t, 100)

    # t=500
    Clock.advance(500)
    Percentile.record(:t, 200)

    # t=900: both still live (ages 900 and 400 < 1000)
    Clock.advance(400)
    assert {:ok, 100} = Percentile.query(:t, 0.0)
    assert {:ok, 200} = Percentile.query(:t, 1.0)

    # t=1100: sample@0 age 1100 >= 1000 -> expired; sample@500 age 600 live
    Clock.advance(200)
    assert {:ok, 200} = Percentile.query(:t, 0.0)
    assert {:ok, 200} = Percentile.query(:t, 1.0)
  end
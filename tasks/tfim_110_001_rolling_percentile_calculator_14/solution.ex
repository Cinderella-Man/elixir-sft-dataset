  test "sample expires exactly at the window boundary" do
    start_server(window_ms: 1_000)

    Percentile.record(:t, 42)

    # t=999: age 999 < 1000 -> still live
    Clock.advance(999)
    assert {:ok, 42} = Percentile.query(:t, 0.5)

    # t=1000: age 1000 >= 1000 -> expired
    Clock.advance(1)
    assert {:error, :empty} = Percentile.query(:t, 0.5)
  end
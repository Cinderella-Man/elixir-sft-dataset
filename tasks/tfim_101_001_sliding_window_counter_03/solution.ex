  test "single increment is counted within the window", %{sc: sc} do
    SlidingCounter.increment(sc, "k")
    assert 1 = SlidingCounter.count(sc, "k", 1_000)
  end
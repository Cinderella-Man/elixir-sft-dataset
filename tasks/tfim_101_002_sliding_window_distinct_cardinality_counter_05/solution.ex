  test "distinct members are all counted within the window", %{sc: sc} do
    for m <- ["u1", "u2", "u3", "u4", "u5"] do
      SlidingUniqueCounter.add(sc, "k", m)
    end

    assert 5 = SlidingUniqueCounter.distinct_count(sc, "k", 1_000)
  end
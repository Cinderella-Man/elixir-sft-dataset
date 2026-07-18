  test "arbitrary terms work as keys and are matched by value", %{sc: sc} do
    tuple_key = {:page, 1, ["a"]}
    equal_tuple_key = {:page, 1, ["a"]}
    other_tuple_key = {:page, 2, ["a"]}

    SlidingCounter.increment(sc, tuple_key)
    SlidingCounter.increment(sc, equal_tuple_key)
    SlidingCounter.increment(sc, :atom_key)
    SlidingCounter.increment(sc, other_tuple_key)

    # The value-equal tuple is the same key, so both increments land together.
    assert 2 = SlidingCounter.count(sc, equal_tuple_key, 1_000)
    assert 1 = SlidingCounter.count(sc, :atom_key, 1_000)
    assert 1 = SlidingCounter.count(sc, other_tuple_key, 1_000)
    assert 0 = SlidingCounter.count(sc, "page", 1_000)
  end
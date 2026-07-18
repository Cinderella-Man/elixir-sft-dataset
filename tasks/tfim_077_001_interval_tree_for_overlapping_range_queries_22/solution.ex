  test "older tree values stay unchanged after many derived inserts" do
    t0 = IntervalTree.new()
    t1 = t0 |> IntervalTree.insert({1, 5}) |> IntervalTree.insert({10, 20})
    before = Enum.sort(IntervalTree.overlapping(t1, {0, 100}))
    assert before == [{1, 5}, {10, 20}]

    _t2 =
      Enum.reduce(1..60, t1, fn i, acc ->
        IntervalTree.insert(acc, {i, i + 3})
      end)

    assert Enum.sort(IntervalTree.overlapping(t1, {0, 100})) == before
    assert Enum.sort(IntervalTree.enclosing(t1, 12)) == [{10, 20}]
    assert IntervalTree.overlapping(t0, {0, 100}) == []
    assert IntervalTree.enclosing(t0, 12) == []
  end
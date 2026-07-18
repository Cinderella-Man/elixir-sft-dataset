  test "insert is non-destructive — original tree is unchanged" do
    t0 = IntervalTree.new()
    t1 = IntervalTree.insert(t0, {1, 5})
    t2 = IntervalTree.insert(t1, {10, 20})

    assert [] = IntervalTree.overlapping(t0, {1, 100})
    assert [{1, 5}] = IntervalTree.overlapping(t1, {1, 100})

    result = IntervalTree.overlapping(t2, {1, 100})
    assert length(result) == 2
    assert {1, 5} in result
    assert {10, 20} in result
  end
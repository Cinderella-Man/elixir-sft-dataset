  test "insert is non-destructive and every earlier tree stays queryable" do
    t1 = build([{1, 5}])
    t2 = T.insert(t1, {10, 20})
    t3 = T.insert(t2, {2, 3})

    assert T.size(t1) == 1
    refute T.member?(t1, {10, 20})
    assert [{1, 5}] = T.overlapping(t1, {0, 100})
    assert [] = T.enclosing(t1, 15)

    assert T.size(t2) == 2
    refute T.member?(t2, {2, 3})
    assert T.member?(t2, {10, 20})
    assert [{10, 20}] = T.enclosing(t2, 15)

    assert T.size(t3) == 3
    assert T.member?(t3, {2, 3})
  end
  test "delete is non-destructive" do
    t1 = build([{1, 5}, {10, 20}])
    {:ok, t2} = T.delete(t1, {1, 5})

    # original still has the interval
    assert T.member?(t1, {1, 5})
    assert [{1, 5}] = T.overlapping(t1, {1, 3})

    # new tree does not
    refute T.member?(t2, {1, 5})
    assert [] = T.overlapping(t2, {1, 3})
  end
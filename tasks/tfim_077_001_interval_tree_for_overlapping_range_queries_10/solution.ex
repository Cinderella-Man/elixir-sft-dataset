  test "query touching the start of an interval still matches" do
    tree = IntervalTree.new() |> IntervalTree.insert({5, 10})
    assert [{5, 10}] = IntervalTree.overlapping(tree, {2, 5})
  end
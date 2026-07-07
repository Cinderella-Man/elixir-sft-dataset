  test "query touching the end of an interval still matches" do
    tree = IntervalTree.new() |> IntervalTree.insert({1, 5})
    assert [{1, 5}] = IntervalTree.overlapping(tree, {5, 8})
  end
  test "degenerate interval is missed when query does not cover its point" do
    tree = IntervalTree.new() |> IntervalTree.insert({4, 4})
    assert [] = IntervalTree.overlapping(tree, {5, 10})
  end
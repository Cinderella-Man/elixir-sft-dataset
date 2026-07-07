  test "degenerate interval is found when query covers its point" do
    tree = IntervalTree.new() |> IntervalTree.insert({4, 4})
    assert [{4, 4}] = IntervalTree.overlapping(tree, {1, 10})
  end
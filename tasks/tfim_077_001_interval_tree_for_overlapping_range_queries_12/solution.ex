  test "degenerate interval is found by enclosing at its exact point" do
    tree = IntervalTree.new() |> IntervalTree.insert({4, 4})
    assert [{4, 4}] = IntervalTree.enclosing(tree, 4)
  end
  test "single interval is found by overlapping query that contains it" do
    tree = IntervalTree.new() |> IntervalTree.insert({3, 7})
    assert [{3, 7}] = IntervalTree.overlapping(tree, {1, 10})
  end
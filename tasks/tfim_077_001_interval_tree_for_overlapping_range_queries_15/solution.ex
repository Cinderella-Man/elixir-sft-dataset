  test "only overlapping intervals are returned, not all" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 2})
      |> IntervalTree.insert({5, 8})
      |> IntervalTree.insert({10, 15})
      |> IntervalTree.insert({20, 25})

    result = IntervalTree.overlapping(tree, {6, 12})
    assert length(result) == 2
    assert {5, 8} in result
    assert {10, 15} in result
  end
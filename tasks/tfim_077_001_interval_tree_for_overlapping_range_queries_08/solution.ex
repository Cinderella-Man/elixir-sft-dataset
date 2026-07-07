  test "touching intervals are considered overlapping" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 5})
      |> IntervalTree.insert({5, 10})

    result = IntervalTree.overlapping(tree, {5, 5})
    assert length(result) == 2
    assert {1, 5} in result
    assert {5, 10} in result
  end
  test "enclosing returns all intervals that contain the point" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 10})
      |> IntervalTree.insert({3, 7})
      |> IntervalTree.insert({6, 15})
      |> IntervalTree.insert({20, 30})

    result = IntervalTree.enclosing(tree, 6)
    assert length(result) == 3
    assert {1, 10} in result
    assert {3, 7} in result
    assert {6, 15} in result
    refute {20, 30} in result
  end
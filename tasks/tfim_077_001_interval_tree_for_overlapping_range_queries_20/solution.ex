  test "overlapping query ending exactly at duplicated starts returns every stored copy" do
    tree =
      IntervalTree.new()
      |> IntervalTree.insert({1, 8})
      |> IntervalTree.insert({6, 7})
      |> IntervalTree.insert({4, 4})
      |> IntervalTree.insert({10, 10})
      |> IntervalTree.insert({10, 10})

    # {10, 10} is stored twice; both share point 10 with each query below.
    assert Enum.sort(IntervalTree.overlapping(tree, {10, 10})) == [{10, 10}, {10, 10}]
    assert Enum.sort(IntervalTree.overlapping(tree, {9, 10})) == [{10, 10}, {10, 10}]

    assert Enum.sort(IntervalTree.overlapping(tree, {0, 10})) ==
             [{1, 8}, {4, 4}, {6, 7}, {10, 10}, {10, 10}]
  end
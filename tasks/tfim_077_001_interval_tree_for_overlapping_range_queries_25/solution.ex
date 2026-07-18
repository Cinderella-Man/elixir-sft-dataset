  test "several intervals sharing one start are all retained and queryable" do
    tree =
      Enum.reduce([{4, 4}, {4, 6}, {4, 100}, {4, 6}, {1, 2}], IntervalTree.new(), fn iv, acc ->
        IntervalTree.insert(acc, iv)
      end)

    assert Enum.sort(IntervalTree.enclosing(tree, 4)) == [{4, 4}, {4, 6}, {4, 6}, {4, 100}]
    assert Enum.sort(IntervalTree.overlapping(tree, {5, 5})) == [{4, 6}, {4, 6}, {4, 100}]
    assert IntervalTree.enclosing(tree, 50) == [{4, 100}]

    assert Enum.sort(IntervalTree.overlapping(tree, {0, 4})) ==
             [{1, 2}, {4, 4}, {4, 6}, {4, 6}, {4, 100}]
  end
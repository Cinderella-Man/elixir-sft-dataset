  test "repeated identical queries on one tree value return the same multiset" do
    tree =
      Enum.reduce([{2, 8}, {2, 8}, {5, 5}, {9, 11}], IntervalTree.new(), fn iv, acc ->
        IntervalTree.insert(acc, iv)
      end)

    first = Enum.sort(IntervalTree.overlapping(tree, {4, 6}))
    _ = IntervalTree.enclosing(tree, 5)
    _ = IntervalTree.overlapping(tree, {0, 100})
    second = Enum.sort(IntervalTree.overlapping(tree, {4, 6}))

    assert first == [{2, 8}, {2, 8}, {5, 5}]
    assert second == first
    assert Enum.sort(IntervalTree.enclosing(tree, 5)) == [{2, 8}, {2, 8}, {5, 5}]
    assert Enum.sort(IntervalTree.enclosing(tree, 5)) == [{2, 8}, {2, 8}, {5, 5}]
  end
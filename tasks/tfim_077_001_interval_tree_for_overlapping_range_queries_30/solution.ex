  test "many copies of one interval are all stored and returned" do
    tree =
      Enum.reduce(1..50, IntervalTree.new(), fn _i, acc ->
        IntervalTree.insert(acc, {5, 9})
      end)

    assert length(IntervalTree.enclosing(tree, 7)) == 50
    assert length(IntervalTree.enclosing(tree, 5)) == 50
    assert length(IntervalTree.overlapping(tree, {9, 12})) == 50
    assert IntervalTree.overlapping(tree, {10, 12}) == []
    assert IntervalTree.enclosing(tree, 4) == []
  end
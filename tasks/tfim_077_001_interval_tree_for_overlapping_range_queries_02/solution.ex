  test "overlapping on empty tree returns empty list" do
    tree = IntervalTree.new()
    assert [] = IntervalTree.overlapping(tree, {1, 10})
  end
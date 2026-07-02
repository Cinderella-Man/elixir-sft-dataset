  test "enclosing on empty tree returns empty list" do
    tree = IntervalTree.new()
    assert [] = IntervalTree.enclosing(tree, 5)
  end
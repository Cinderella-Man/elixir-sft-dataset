  test "empty tree queries" do
    tree = T.new()
    assert [] = T.overlapping(tree, {1, 10})
    assert [] = T.enclosing(tree, 5)
    assert T.size(tree) == 0
    refute T.member?(tree, {1, 2})
  end
  test "degenerate interval found by exact point" do
    tree = build([{4, 4}])
    assert [{4, 4}] = T.enclosing(tree, 4)
    assert [] = T.enclosing(tree, 5)
  end
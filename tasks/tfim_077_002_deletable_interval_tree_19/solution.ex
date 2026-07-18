  test "enclosing includes both endpoints and excludes points just outside" do
    tree = build([{1, 10}, {12, 20}])

    assert [{1, 10}] = T.enclosing(tree, 1)
    assert [{1, 10}] = T.enclosing(tree, 10)
    assert [] = T.enclosing(tree, 0)
    assert [] = T.enclosing(tree, 11)
    assert [{12, 20}] = T.enclosing(tree, 12)
    assert [{12, 20}] = T.enclosing(tree, 20)
    assert [] = T.enclosing(tree, 21)
  end
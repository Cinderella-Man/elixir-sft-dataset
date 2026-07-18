  test "pruning keeps an interval that ends exactly where the query starts" do
    tree = build([{1, 5}])

    assert [{1, 5}] = T.overlapping(tree, {5, 9})
    assert [{1, 5}] = T.enclosing(tree, 5)
    assert [{1, 5}] = T.overlapping(tree, {1, 1})
    assert [{1, 5}] = T.enclosing(tree, 1)

    assert [] = T.overlapping(tree, {6, 9})
    assert [] = T.enclosing(tree, 6)
    assert [] = T.overlapping(tree, {-3, 0})
    assert [] = T.enclosing(tree, 0)
  end
  test "queries include right-subtree matches that start exactly at the query end" do
    tree = build([{1, 1}, {5, 5}, {5, 9}])

    assert Enum.sort(T.overlapping(tree, {3, 5})) == [{5, 5}, {5, 9}]
    assert Enum.sort(T.enclosing(tree, 5)) == [{5, 5}, {5, 9}]
    assert Enum.sort(T.overlapping(tree, {0, 1})) == [{1, 1}]
    assert Enum.sort(T.overlapping(tree, {6, 6})) == [{5, 9}]
    assert Enum.sort(T.overlapping(tree, {0, 9})) == [{1, 1}, {5, 5}, {5, 9}]
  end
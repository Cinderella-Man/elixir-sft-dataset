  test "both stored copies of a duplicate interval are returned by queries" do
    tree = build([{2, 8}, {2, 8}, {30, 40}])

    assert T.size(tree) == 3
    assert T.member?(tree, {2, 8})
    assert Enum.sort(T.overlapping(tree, {1, 10})) == [{2, 8}, {2, 8}]
    assert Enum.sort(T.enclosing(tree, 5)) == [{2, 8}, {2, 8}]
    assert Enum.sort(T.overlapping(tree, {0, 100})) == [{2, 8}, {2, 8}, {30, 40}]
  end
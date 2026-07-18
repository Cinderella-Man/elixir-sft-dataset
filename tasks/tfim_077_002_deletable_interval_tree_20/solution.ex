  test "deleting the widest interval keeps later queries correct" do
    tree = build([{0, 1000}, {5, 6}, {10, 11}, {20, 21}, {30, 31}, {40, 41}])

    assert {:ok, tree2} = T.delete(tree, {0, 1000})
    refute T.member?(tree2, {0, 1000})
    assert [] = T.enclosing(tree2, 500)
    assert [{20, 21}] = T.overlapping(tree2, {15, 25})

    assert Enum.sort(T.overlapping(tree2, {0, 1000})) ==
             [{5, 6}, {10, 11}, {20, 21}, {30, 31}, {40, 41}]

    assert T.member?(tree, {0, 1000})
    assert [{0, 1000}] = T.enclosing(tree, 500)
  end
  test "delete removes an existing interval and returns :ok tuple" do
    tree = build([{1, 5}, {10, 20}, {30, 40}])
    assert {:ok, tree2} = T.delete(tree, {10, 20})
    refute T.member?(tree2, {10, 20})
    assert T.size(tree2) == 2
    assert [] = T.overlapping(tree2, {12, 15})
  end
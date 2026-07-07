  test "delete removes only one of two identical intervals" do
    tree = build([{2, 8}, {2, 8}])
    assert T.size(tree) == 2
    assert {:ok, tree2} = T.delete(tree, {2, 8})
    assert T.size(tree2) == 1
    assert T.member?(tree2, {2, 8})
    assert [{2, 8}] = T.overlapping(tree2, {1, 10})
    assert {:ok, tree3} = T.delete(tree2, {2, 8})
    assert T.size(tree3) == 0
    assert {:error, :not_found} = T.delete(tree3, {2, 8})
  end
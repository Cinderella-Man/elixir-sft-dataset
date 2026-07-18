  test "degenerate intervals support overlap, membership and one-at-a-time deletion" do
    tree = build([{4, 4}, {4, 4}, {7, 7}])

    assert T.member?(tree, {4, 4})
    assert Enum.sort(T.overlapping(tree, {4, 4})) == [{4, 4}, {4, 4}]
    assert Enum.sort(T.overlapping(tree, {3, 8})) == [{4, 4}, {4, 4}, {7, 7}]

    assert {:ok, tree2} = T.delete(tree, {4, 4})
    assert T.size(tree2) == 2
    assert [{4, 4}] = T.enclosing(tree2, 4)

    assert {:ok, tree3} = T.delete(tree2, {4, 4})
    refute T.member?(tree3, {4, 4})
    assert {:error, :not_found} = T.delete(tree3, {4, 4})
    assert [{7, 7}] = T.overlapping(tree3, {0, 100})
  end
  test "deleting the root repeatedly keeps the tree valid" do
    tree = build(for i <- 1..50, do: {i, i + 3})

    tree =
      Enum.reduce(1..50, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i, i + 3})
        acc2
      end)

    assert T.size(tree) == 0
    assert [] = T.overlapping(tree, {1, 1000})
  end
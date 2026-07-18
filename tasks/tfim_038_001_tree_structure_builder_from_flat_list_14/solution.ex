  test "no false positive on a wide flat tree (many siblings)" do
    items =
      [%{id: 0, parent_id: nil}] ++
        for(i <- 1..50, do: %{id: i, parent_id: 0})

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert length(root.children) == 50
  end
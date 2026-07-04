  test "pre-order visits a whole subtree before the next sibling" do
    # 1 -> 2 -> 4
    #      2 -> 5
    # 1 -> 3
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 4, parent_id: 2},
      %{id: 5, parent_id: 2}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1, 2, 4, 5, 3]
  end
  test "subtree returns node plus all descendants in pre-order" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 4, parent_id: 2},
      %{id: 5, parent_id: 2}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert {:ok, slice} = TreePaths.subtree(nodes, 2)
    assert ids(slice) == [2, 4, 5]
  end
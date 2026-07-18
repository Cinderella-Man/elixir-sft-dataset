  test "subtree of a leaf is just the leaf" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert {:ok, [only]} = TreePaths.subtree(nodes, 2)
    assert only.id == 2
  end
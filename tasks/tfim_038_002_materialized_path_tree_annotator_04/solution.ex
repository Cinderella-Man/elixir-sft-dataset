  test "parent-child emitted in pre-order with accumulating path" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1, 2]

    [root, child] = nodes
    assert root.depth == 0 and root.path == [1]
    assert child.depth == 1 and child.path == [1, 2]
  end
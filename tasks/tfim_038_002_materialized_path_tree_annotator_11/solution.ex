  test ":raise_to_root turns an orphan into a root with its own subtree" do
    items = [
      %{id: 2, parent_id: 99},
      %{id: 3, parent_id: 2}
    ]

    assert {:ok, nodes} = TreePaths.build(items, orphan_strategy: :raise_to_root)
    assert ids(nodes) == [2, 3]

    [orphan, child] = nodes
    assert orphan.depth == 0 and orphan.path == [2]
    assert child.depth == 1 and child.path == [2, 3]
  end
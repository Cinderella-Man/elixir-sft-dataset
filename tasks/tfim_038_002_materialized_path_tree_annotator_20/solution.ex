  test "subtree of a root spans grandchildren and excludes other roots" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2},
      %{id: 4, parent_id: nil},
      %{id: 5, parent_id: 4}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert {:ok, slice} = TreePaths.subtree(nodes, 1)
    assert ids(slice) == [1, 2, 3]
    assert Enum.map(slice, & &1.depth) == [0, 1, 2]
  end
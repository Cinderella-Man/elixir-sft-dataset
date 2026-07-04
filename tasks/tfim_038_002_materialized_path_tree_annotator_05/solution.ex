  test "deep tree accumulates full ancestor path and increasing depth" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1, 2, 3]
    assert Enum.map(nodes, & &1.depth) == [0, 1, 2]
    assert Enum.map(nodes, & &1.path) == [[1], [1, 2], [1, 2, 3]]
  end
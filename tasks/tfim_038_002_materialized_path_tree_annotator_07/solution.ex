  test "children preserve original input order" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 4, parent_id: 1},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1, 4, 2, 3]
  end
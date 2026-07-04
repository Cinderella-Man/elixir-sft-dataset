  test "node with multiple children preserves input order" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 4, parent_id: 1}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert Enum.map(root.children, & &1.id) == [2, 3, 4]
  end
  test "multiple roots each with their own subtrees" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 10, parent_id: nil},
      %{id: 11, parent_id: 10},
      %{id: 12, parent_id: 10}
    ]

    assert {:ok, [root1, root2]} = TreeBuilder.build(items)

    assert root1.id == 1
    assert [%{id: 2}] = root1.children

    assert root2.id == 10
    assert Enum.map(root2.children, & &1.id) == [11, 12]
  end
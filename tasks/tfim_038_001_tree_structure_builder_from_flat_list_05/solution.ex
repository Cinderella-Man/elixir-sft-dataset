  test "three-level deep tree" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.id == 1
    assert [level2] = root.children
    assert level2.id == 2
    assert [level3] = level2.children
    assert level3.id == 3
    assert level3.children == []
  end
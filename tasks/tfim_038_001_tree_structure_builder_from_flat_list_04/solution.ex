  test "simple parent-child relationship" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.id == 1
    assert [child] = root.children
    assert child.id == 2
    assert child.children == []
  end
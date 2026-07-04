  test "multiple root nodes are returned" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: nil},
      %{id: 3, parent_id: nil}
    ]

    assert {:ok, roots} = TreeBuilder.build(items)
    assert Enum.map(roots, & &1.id) == [1, 2, 3]
    assert Enum.all?(roots, &(&1.children == []))
  end
  test "clean input returns {:ok, forest}" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1}
    ]

    assert {:ok, [root]} = TreeValidator.build(items)
    assert root.id == 1
    assert Enum.map(root.children, & &1.id) == [2, 3]
  end
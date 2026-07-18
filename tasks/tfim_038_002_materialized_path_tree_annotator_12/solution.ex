  test "direct cycle returns error" do
    items = [
      %{id: 1, parent_id: 2},
      %{id: 2, parent_id: 1}
    ]

    assert {:error, {:cycle_detected, ids}} = TreePaths.build(items)
    assert Enum.sort(ids) == [1, 2]
  end
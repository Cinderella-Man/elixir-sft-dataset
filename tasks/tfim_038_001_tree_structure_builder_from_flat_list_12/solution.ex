  test "indirect cycle A -> B -> C -> A returns error" do
    items = [
      %{id: 1, parent_id: 3},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2}
    ]

    assert {:error, {:cycle_detected, ids}} = TreeBuilder.build(items)
    assert is_list(ids)
    assert Enum.sort(ids) == [1, 2, 3]
  end
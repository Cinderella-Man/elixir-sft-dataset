  test "direct cycle A -> B -> A returns error" do
    items = [
      %{id: 1, parent_id: 2},
      %{id: 2, parent_id: 1}
    ]

    assert {:error, {:cycle_detected, ids}} = TreeBuilder.build(items)
    assert is_list(ids)
    assert 1 in ids
    assert 2 in ids
  end
  test "cycle unreachable from any root still returns an error" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: :x, parent_id: :y},
      %{id: :y, parent_id: :x}
    ]

    assert {:error, {:cycle_detected, cycle_ids}} = TreePaths.build(items)
    assert Enum.sort(cycle_ids) == [:x, :y]
  end
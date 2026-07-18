  test "two disjoint cycles are reported as separate entries" do
    items = [
      %{id: 1, parent_id: 2},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 4},
      %{id: 4, parent_id: 3}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert forest == []

    cycles = Enum.filter(issues, &(&1.type == :cycle))
    assert length(cycles) == 2

    all_cycle_ids = cycles |> Enum.flat_map(& &1.ids) |> Enum.sort()
    assert all_cycle_ids == [1, 2, 3, 4]
  end
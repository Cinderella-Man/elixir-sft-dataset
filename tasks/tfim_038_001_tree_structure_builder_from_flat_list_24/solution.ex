  test "cycle inside an otherwise valid input errors with only the cycle ids" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 10, parent_id: 11},
      %{id: 11, parent_id: 10}
    ]

    assert {:error, {:cycle_detected, ids}} = TreeBuilder.build(items)
    assert Enum.sort(ids) == [10, 11]
  end
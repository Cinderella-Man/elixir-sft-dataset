  test "every duplicated id is reported exactly once when several ids repeat" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 2, parent_id: 1}
    ]

    assert {:error, {:duplicate_ids, ids}} = TreeBuilder.build(items)
    assert Enum.sort(ids) == [1, 2]
  end
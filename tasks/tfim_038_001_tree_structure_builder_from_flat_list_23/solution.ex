  test "a duplicated id is rejected with the duplicate list" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 1, parent_id: nil}
    ]

    assert {:error, {:duplicate_ids, [1]}} = TreeBuilder.build(items)
  end
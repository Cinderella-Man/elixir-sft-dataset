  test "diamond-shaped branches listed deepest-first are not reported as a cycle" do
    items = [
      %{id: 4, parent_id: 2},
      %{id: 5, parent_id: 3},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 1, parent_id: nil}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert collect_ids([root]) == [1, 2, 4, 3, 5]
  end
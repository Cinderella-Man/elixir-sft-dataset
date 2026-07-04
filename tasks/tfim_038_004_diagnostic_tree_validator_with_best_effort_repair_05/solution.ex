  test "duplicate ids: first kept, later dropped, reported" do
    items = [
      %{id: 1, parent_id: nil, v: :first},
      %{id: 2, parent_id: 1},
      %{id: 1, parent_id: nil, v: :second}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert [root] = forest
    assert root.v == :first
    assert Enum.map(root.children, & &1.id) == [2]

    dup = issue(issues, :duplicate_id)
    assert dup.ids == [1]
  end
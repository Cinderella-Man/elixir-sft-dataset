  test "multiple issue types are ordered dup, missing_parent, orphan, cycle" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 1, parent_id: nil},
      %{id: 2},
      %{id: 3, parent_id: 88},
      %{id: 4, parent_id: 5},
      %{id: 5, parent_id: 4}
    ]

    assert {:issues, _forest, issues} = TreeValidator.build(items)
    types = Enum.map(issues, & &1.type)
    assert types == [:duplicate_id, :missing_parent_id, :orphan, :cycle]
  end
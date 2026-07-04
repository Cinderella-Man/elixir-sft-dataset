  test "indirect cycle is detected and its nodes removed" do
    items = [
      %{id: 1, parent_id: 3},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert forest == []

    cyc = issue(issues, :cycle)
    assert Enum.sort(cyc.ids) == [1, 2, 3]
  end
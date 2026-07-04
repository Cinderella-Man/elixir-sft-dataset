  test "direct cycle: nodes dropped, cycle reported" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 3},
      %{id: 3, parent_id: 2}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert collect_ids(forest) == [1]

    cyc = issue(issues, :cycle)
    assert Enum.sort(cyc.ids) == [2, 3]
  end
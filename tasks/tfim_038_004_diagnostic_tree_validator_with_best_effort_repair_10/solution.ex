  test "a node pointing into a removed cycle becomes an orphan" do
    items = [
      %{id: 1, parent_id: nil},
      # cycle 2 <-> 3
      %{id: 2, parent_id: 3},
      %{id: 3, parent_id: 2},
      # 4 references a cycle node that gets removed
      %{id: 4, parent_id: 3}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert Enum.sort(collect_ids(forest)) == [1, 4]

    cyc = issue(issues, :cycle)
    assert Enum.sort(cyc.ids) == [2, 3]

    orphan = issue(issues, :orphan)
    assert orphan.ids == [4]
  end
  test "missing :parent_id key is treated as a root and reported" do
    items = [
      %{id: 1, parent_id: nil},
      # no :parent_id key at all
      %{id: 2},
      %{id: 3, parent_id: 2}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    ids = collect_ids(forest)
    assert Enum.sort(ids) == [1, 2, 3]

    node2 = Enum.find(forest, &(&1.id == 2))
    assert [%{id: 3}] = node2.children

    mp = issue(issues, :missing_parent_id)
    assert mp.ids == [2]
  end
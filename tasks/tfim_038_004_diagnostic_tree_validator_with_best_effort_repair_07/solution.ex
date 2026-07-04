  test "orphan is raised to root and reported" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 99},
      %{id: 3, parent_id: 2}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert Enum.sort(collect_ids(forest)) == [1, 2, 3]

    orphan_root = Enum.find(forest, &(&1.id == 2))
    assert [%{id: 3}] = orphan_root.children

    orphan = issue(issues, :orphan)
    assert orphan.ids == [2]
  end
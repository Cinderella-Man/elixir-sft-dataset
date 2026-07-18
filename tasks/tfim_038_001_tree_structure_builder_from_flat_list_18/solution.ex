  test ":raise_to_root orphan carries its own children" do
    items = [
      # orphan
      %{id: 2, parent_id: 99},
      # child of orphan
      %{id: 3, parent_id: 2}
    ]

    assert {:ok, roots} = TreeBuilder.build(items, orphan_strategy: :raise_to_root)
    orphan_root = Enum.find(roots, &(&1.id == 2))
    assert orphan_root != nil
    assert [%{id: 3}] = orphan_root.children
  end
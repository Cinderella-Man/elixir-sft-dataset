  test ":raise_to_root attaches orphans as root nodes" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 99}
    ]

    assert {:ok, roots} = TreeBuilder.build(items, orphan_strategy: :raise_to_root)
    all_ids = collect_ids(roots)
    assert 1 in all_ids
    assert 2 in all_ids
  end
  test "orphans are discarded with explicit :discard option" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 99}
    ]

    assert {:ok, roots} = TreeBuilder.build(items, orphan_strategy: :discard)
    refute 2 in collect_ids(roots)
  end
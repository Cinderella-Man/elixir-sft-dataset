  test "orphans are discarded by default" do
    items = [
      %{id: 1, parent_id: nil},
      # 99 does not exist
      %{id: 2, parent_id: 99}
    ]

    assert {:ok, roots} = TreeBuilder.build(items)
    all_ids = collect_ids(roots)
    assert 1 in all_ids
    refute 2 in all_ids
  end
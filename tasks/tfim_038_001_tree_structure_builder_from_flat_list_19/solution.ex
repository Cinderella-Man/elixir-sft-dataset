  test "multiple orphans all raised to root" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: :missing},
      %{id: 3, parent_id: :also_missing}
    ]

    assert {:ok, roots} = TreeBuilder.build(items, orphan_strategy: :raise_to_root)
    ids = Enum.map(roots, & &1.id) |> MapSet.new()
    assert MapSet.equal?(ids, MapSet.new([1, 2, 3]))
  end
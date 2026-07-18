  test "an indirect cycle is still detected when orphans are raised to root" do
    items = [
      %{id: :r, parent_id: nil},
      %{id: :o, parent_id: :nowhere},
      %{id: :a, parent_id: :c},
      %{id: :b, parent_id: :a},
      %{id: :c, parent_id: :b}
    ]

    opts = [orphan_strategy: :raise_to_root]
    assert {:error, {:cycle_detected, ids}} = TreeBuilder.build(items, opts)
    assert Enum.sort(ids) == [:a, :b, :c]
  end
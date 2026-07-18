  test "sibling order is preserved when children of different parents interleave" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: nil},
      %{id: :a1, parent_id: 1},
      %{id: :b1, parent_id: 2},
      %{id: :a2, parent_id: 1},
      %{id: :b2, parent_id: 2},
      %{id: :a3, parent_id: 1}
    ]

    assert {:ok, [r1, r2]} = TreeBuilder.build(items)
    assert Enum.map(r1.children, & &1.id) == [:a1, :a2, :a3]
    assert Enum.map(r2.children, & &1.id) == [:b1, :b2]
  end
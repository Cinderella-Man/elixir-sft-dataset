  test "input given in child-first order still builds correctly" do
    items = [
      %{id: 3, parent_id: 2},
      %{id: 2, parent_id: 1},
      %{id: 1, parent_id: nil}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.id == 1
    assert [%{id: 2, children: [%{id: 3}]}] = root.children
  end
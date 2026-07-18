  test "complex tree: two roots, mixed depths, correct structure" do
    # Tree A:  1 -> 2 -> 4
    #               2 -> 5
    #          1 -> 3
    # Tree B: 10 -> 11
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 4, parent_id: 2},
      %{id: 5, parent_id: 2},
      %{id: 10, parent_id: nil},
      %{id: 11, parent_id: 10}
    ]

    assert {:ok, [root_a, root_b]} = TreeBuilder.build(items)

    assert root_a.id == 1
    assert length(root_a.children) == 2
    [child2, child3] = root_a.children
    assert child2.id == 2
    assert child3.id == 3
    assert Enum.map(child2.children, & &1.id) == [4, 5]
    assert child3.children == []

    assert root_b.id == 10
    assert [%{id: 11, children: []}] = root_b.children
  end
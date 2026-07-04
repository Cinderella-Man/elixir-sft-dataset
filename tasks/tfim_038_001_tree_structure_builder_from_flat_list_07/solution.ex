  test "all original fields are preserved on nodes" do
    items = [
      %{id: "a", parent_id: nil, label: "Alpha", score: 42},
      %{id: "b", parent_id: "a", label: "Beta", score: 7}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.label == "Alpha"
    assert root.score == 42
    assert [child] = root.children
    assert child.label == "Beta"
    assert child.score == 7
  end
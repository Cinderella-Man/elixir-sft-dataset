  test "all original fields are preserved alongside annotations" do
    items = [
      %{id: "a", parent_id: nil, label: "Alpha", score: 42},
      %{id: "b", parent_id: "a", label: "Beta", score: 7}
    ]

    assert {:ok, [root, child]} = TreePaths.build(items)
    assert root.label == "Alpha" and root.score == 42
    assert child.label == "Beta" and child.score == 7
    assert child.path == ["a", "b"]
  end
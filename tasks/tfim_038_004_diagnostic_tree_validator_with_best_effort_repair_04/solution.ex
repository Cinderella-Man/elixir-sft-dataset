  test "preserves original fields on a clean build" do
    items = [
      %{id: "a", parent_id: nil, label: "Alpha"},
      %{id: "b", parent_id: "a", label: "Beta"}
    ]

    assert {:ok, [root]} = TreeValidator.build(items)
    assert root.label == "Alpha"
    assert [child] = root.children
    assert child.label == "Beta"
  end
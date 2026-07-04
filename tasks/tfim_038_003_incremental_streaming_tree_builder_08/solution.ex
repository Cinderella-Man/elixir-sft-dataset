  test "preserves all original fields" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: "a", parent_id: nil, label: "Alpha", score: 42})
    TreeStream.add(pid, %{id: "b", parent_id: "a", label: "Beta", score: 7})

    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.label == "Alpha" and root.score == 42
    assert [child] = root.children
    assert child.label == "Beta" and child.score == 7
    TreeStream.stop(pid)
  end
  test "compare_fields restricts the diff but records stay complete" do
    pid = start!(key_fields: [:id], compare_fields: [:name])

    StreamReconciler.push_left(pid, %{id: 1, name: "Alice", internal: "old"})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, name: "Alice", internal: "new"})

    assert entry.differences == %{}
    assert entry.left.internal == "old"
    assert entry.right.internal == "new"
  end
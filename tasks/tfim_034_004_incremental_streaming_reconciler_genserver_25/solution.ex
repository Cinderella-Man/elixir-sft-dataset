  test "values that are equal under == but not identical are not reported as differences" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, amount: 1})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, amount: 1.0})

    assert entry.differences == %{}
    assert entry.left == %{id: 1, amount: 1}
    assert entry.right == %{id: 1, amount: 1.0}
  end
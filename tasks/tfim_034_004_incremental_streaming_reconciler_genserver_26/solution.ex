  test "an empty compare_fields list diffs nothing while records stay complete" do
    pid = start!(key_fields: [:id], compare_fields: [])

    StreamReconciler.push_left(pid, %{id: 1, a: 1, b: 2})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, a: 9, b: 8})

    assert entry.differences == %{}
    assert entry.left == %{id: 1, a: 1, b: 2}
    assert entry.right == %{id: 1, a: 9, b: 8}
  end
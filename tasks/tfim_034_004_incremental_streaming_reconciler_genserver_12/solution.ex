  test "a compared field missing from one record diffs as nil" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, score: 42})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1})

    assert entry.differences == %{score: %{left: 42, right: nil}}
  end
  test "a completed pair is removed from pending" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    {:matched, _} = StreamReconciler.push_right(pid, %{id: 1})

    assert StreamReconciler.pending(pid) == %{left: [], right: []}
  end
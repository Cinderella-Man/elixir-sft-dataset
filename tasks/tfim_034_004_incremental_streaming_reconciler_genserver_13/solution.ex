  test "key fields never appear in the differences map" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, a: 1})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, a: 2})

    assert entry.differences == %{a: %{left: 1, right: 2}}
  end
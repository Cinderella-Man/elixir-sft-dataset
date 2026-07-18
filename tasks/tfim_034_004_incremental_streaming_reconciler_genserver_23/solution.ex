  test "a duplicate pending right push replaces the older right record" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_right(pid, %{id: 1, v: "first"}) == :pending
    assert StreamReconciler.push_right(pid, %{id: 1, v: "second"}) == :pending

    assert StreamReconciler.pending(pid) == %{left: [], right: [%{id: 1, v: "second"}]}

    {:matched, entry} = StreamReconciler.push_left(pid, %{id: 1, v: "second"})
    assert entry.right == %{id: 1, v: "second"}
    assert entry.differences == %{}
    assert StreamReconciler.pending(pid) == %{left: [], right: []}
  end
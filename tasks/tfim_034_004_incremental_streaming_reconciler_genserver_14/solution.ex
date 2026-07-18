  test "a duplicate pending push on the same side replaces the older record" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, v: "first"}) == :pending
    assert StreamReconciler.push_left(pid, %{id: 1, v: "second"}) == :pending

    assert StreamReconciler.pending(pid) == %{left: [%{id: 1, v: "second"}], right: []}

    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, v: "second"})
    assert entry.left == %{id: 1, v: "second"}
    assert entry.differences == %{}
  end
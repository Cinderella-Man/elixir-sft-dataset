  test "interleaved out-of-order streams reconcile correctly" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, status: "active"})
    StreamReconciler.push_right(pid, %{id: 3, status: "active"})
    StreamReconciler.push_left(pid, %{id: 2, status: "active"})
    StreamReconciler.push_right(pid, %{id: 2, status: "inactive"})
    StreamReconciler.push_right(pid, %{id: 1, status: "active"})
    StreamReconciler.push_left(pid, %{id: 4, status: "new"})

    matches = StreamReconciler.take_matches(pid)
    assert length(matches) == 2
    assert Enum.map(matches, & &1.key) == [%{id: 2}, %{id: 1}]

    bob = Enum.find(matches, &(&1.key == %{id: 2}))
    assert bob.differences == %{status: %{left: "active", right: "inactive"}}

    alice = Enum.find(matches, &(&1.key == %{id: 1}))
    assert alice.differences == %{}

    pending = StreamReconciler.pending(pid)
    assert sorted_ids(pending.left) == [4]
    assert sorted_ids(pending.right) == [3]
  end
  test "an unmatched left push is parked as pending" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, name: "Alice"}) == :pending

    pending = StreamReconciler.pending(pid)
    assert pending.left == [%{id: 1, name: "Alice"}]
    assert pending.right == []
    assert StreamReconciler.take_matches(pid) == []
  end
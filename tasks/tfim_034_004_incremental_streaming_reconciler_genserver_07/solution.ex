  test "an unmatched right push is parked as pending" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_right(pid, %{id: 2}) == :pending

    pending = StreamReconciler.pending(pid)
    assert pending.left == []
    assert pending.right == [%{id: 2}]
  end
  test "composite keys only match when every key field agrees" do
    pid = start!(key_fields: [:org_id, :user_id])

    assert StreamReconciler.push_left(pid, %{org_id: 1, user_id: 10}) == :pending
    assert StreamReconciler.push_right(pid, %{org_id: 2, user_id: 10}) == :pending

    assert {:matched, entry} = StreamReconciler.push_right(pid, %{org_id: 1, user_id: 10})
    assert entry.key == %{org_id: 1, user_id: 10}

    pending = StreamReconciler.pending(pid)
    assert pending.left == []
    assert pending.right == [%{org_id: 2, user_id: 10}]
  end
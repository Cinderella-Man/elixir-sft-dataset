  test "matched entry carries full original records regardless of diffs" do
    left = [%{id: 1, name: "Alice", role: "admin"}]
    right = [%{id: 1, name: "Alice", role: "user"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.left == %{id: 1, name: "Alice", role: "admin"}
    assert entry.right == %{id: 1, name: "Alice", role: "user"}
  end
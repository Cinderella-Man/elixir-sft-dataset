  test "a record missing a key field keys on nil and matches a counterpart missing it too" do
    pid = start!(key_fields: [:org_id, :user_id])

    assert StreamReconciler.push_left(pid, %{user_id: 10, v: "l"}) == :pending
    assert StreamReconciler.pending(pid) == %{left: [%{user_id: 10, v: "l"}], right: []}

    assert {:matched, entry} =
             StreamReconciler.push_right(pid, %{org_id: nil, user_id: 10, v: "r"})

    assert entry.key == %{org_id: nil, user_id: 10}
    assert entry.left == %{user_id: 10, v: "l"}
    assert entry.right == %{org_id: nil, user_id: 10, v: "r"}
    assert entry.differences == %{v: %{left: "l", right: "r"}}

    assert StreamReconciler.pending(pid) == %{left: [], right: []}
  end
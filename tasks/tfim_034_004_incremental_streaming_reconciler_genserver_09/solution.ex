  test "a left push completing a pending right keeps sides straight" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_right(pid, %{id: 1, status: "closed"}) == :pending
    assert {:matched, entry} = StreamReconciler.push_left(pid, %{id: 1, status: "open"})

    assert entry.left == %{id: 1, status: "open"}
    assert entry.right == %{id: 1, status: "closed"}
    assert entry.differences == %{status: %{left: "open", right: "closed"}}
  end
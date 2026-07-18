  test "a third push on a completed key parks as pending and buffers no second entry" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, v: "l"}) == :pending
    assert {:matched, _} = StreamReconciler.push_right(pid, %{id: 1, v: "r"})

    assert StreamReconciler.push_right(pid, %{id: 1, v: "r2"}) == :pending
    assert StreamReconciler.pending(pid) == %{left: [], right: [%{id: 1, v: "r2"}]}

    matches = StreamReconciler.take_matches(pid)
    assert length(matches) == 1
    assert StreamReconciler.take_matches(pid) == []
  end
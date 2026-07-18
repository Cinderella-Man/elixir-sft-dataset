  test "pending does not clear the pending sets" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    assert %{left: [%{id: 1}]} = StreamReconciler.pending(pid)
    assert %{left: [%{id: 1}]} = StreamReconciler.pending(pid)
  end
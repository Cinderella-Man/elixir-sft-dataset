  test "two servers keep independent state" do
    a = start!(key_fields: [:id])
    b = start!(key_fields: [:id])

    StreamReconciler.push_left(a, %{id: 1})
    assert StreamReconciler.pending(b) == %{left: [], right: []}

    assert StreamReconciler.push_right(b, %{id: 1}) == :pending
    assert StreamReconciler.take_matches(a) == []
    assert StreamReconciler.take_matches(b) == []
  end
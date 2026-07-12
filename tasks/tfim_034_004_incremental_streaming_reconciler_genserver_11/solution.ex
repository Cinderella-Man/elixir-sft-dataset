  test "identical records match with an empty differences map" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, name: "Alice"})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, name: "Alice"})

    assert entry.differences == %{}
  end
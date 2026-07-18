  test "take_matches returns entries in completion order and empties the buffer" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    StreamReconciler.push_left(pid, %{id: 2})
    {:matched, _} = StreamReconciler.push_right(pid, %{id: 2})
    {:matched, _} = StreamReconciler.push_right(pid, %{id: 1})

    matches = StreamReconciler.take_matches(pid)
    assert Enum.map(matches, & &1.key) == [%{id: 2}, %{id: 1}]

    assert StreamReconciler.take_matches(pid) == []
  end
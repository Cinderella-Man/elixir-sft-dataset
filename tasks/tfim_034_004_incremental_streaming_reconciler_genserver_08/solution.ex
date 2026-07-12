  test "a right push completing a pending left returns the matched entry" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, name: "Alice", age: 30}) == :pending

    assert {:matched, entry} =
             StreamReconciler.push_right(pid, %{id: 1, name: "Alice", age: 31})

    assert entry.key == %{id: 1}
    assert entry.left == %{id: 1, name: "Alice", age: 30}
    assert entry.right == %{id: 1, name: "Alice", age: 31}
    assert entry.differences == %{age: %{left: 30, right: 31}}
  end
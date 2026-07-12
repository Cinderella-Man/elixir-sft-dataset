  test "one_to_one entry carries key map, full records and differences" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alicia", age: 30}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.one_to_one
    assert entry.key == %{id: 1}
    assert entry.left == %{id: 1, name: "Alice", age: 30}
    assert entry.right == %{id: 1, name: "Alicia", age: 30}
    assert entry.differences == %{name: %{left: "Alice", right: "Alicia"}}
  end
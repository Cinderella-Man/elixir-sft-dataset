  test "compare_fields restricts the diff but records stay complete" do
    left = [%{id: 1, name: "Alice", internal: "old"}]
    right = [%{id: 1, name: "Alice", internal: "new"}]

    report =
      MultiKeyReconciler.classify(left, right, key_fields: [:id], compare_fields: [:name])

    [entry] = report.one_to_one
    assert entry.differences == %{}
    assert entry.left.internal == "old"
    assert entry.right.internal == "new"
  end
  test "many records on both sides produce a many_to_many entry" do
    left = [%{id: 9, v: 1}, %{id: 9, v: 2}]
    right = [%{id: 9, v: 3}, %{id: 9, v: 4}, %{id: 9, v: 5}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.many_to_many
    assert entry.key == %{id: 9}
    assert length(entry.left) == 2
    assert length(entry.right) == 3
    assert entry.left == [%{id: 9, v: 1}, %{id: 9, v: 2}]
  end
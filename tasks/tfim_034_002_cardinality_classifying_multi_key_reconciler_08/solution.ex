  test "one left and many right records produce a one_to_many entry" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Alice A"}, %{id: 1, name: "Alice B"}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    assert report.one_to_one == []
    [entry] = report.one_to_many
    assert entry.key == %{id: 1}
    assert entry.left == %{id: 1, name: "Alice"}
    assert entry.right == [%{id: 1, name: "Alice A"}, %{id: 1, name: "Alice B"}]
    refute Map.has_key?(entry, :differences)
  end
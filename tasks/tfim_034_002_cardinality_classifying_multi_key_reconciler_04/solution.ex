  test "identical one_to_one pair has an empty differences map" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Alice"}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])

    [entry] = report.one_to_one
    assert entry.differences == %{}
  end
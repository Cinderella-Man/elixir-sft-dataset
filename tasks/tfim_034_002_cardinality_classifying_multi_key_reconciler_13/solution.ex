  test "composite keys match only when all key fields are equal" do
    left = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 1, user_id: 20, name: "Bob"}
    ]

    right = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 2, user_id: 10, name: "Charlie"}
    ]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:org_id, :user_id])

    [entry] = report.one_to_one
    assert entry.key == %{org_id: 1, user_id: 10}
    assert length(report.only_in_left) == 1
    assert length(report.only_in_right) == 1
  end
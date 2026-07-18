  test "a record missing a key field keys on nil" do
    left = [%{user_id: 10, v: 1}]
    right = [%{org_id: nil, user_id: 10, v: 2}]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:org_id, :user_id])

    [entry] = report.one_to_one
    assert entry.key == %{org_id: nil, user_id: 10}
  end
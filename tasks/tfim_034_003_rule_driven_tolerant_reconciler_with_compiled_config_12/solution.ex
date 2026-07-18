  test "composite keys match only when all key fields are equal" do
    config = config!(key_fields: [:org_id, :user_id])

    left = [%{org_id: 1, user_id: 10}, %{org_id: 1, user_id: 20}]
    right = [%{org_id: 1, user_id: 10}, %{org_id: 2, user_id: 10}]

    report = TolerantReconciler.run(config, left, right)

    assert length(report.matched) == 1
    assert length(report.only_in_left) == 1
    assert length(report.only_in_right) == 1
  end
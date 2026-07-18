  test "composite keys treat an absent key field as nil on both sides" do
    config = config!(key_fields: [:org_id, :user_id])

    left = [%{org_id: 1, note: "l"}]
    right = [%{org_id: 1, user_id: nil, note: "r"}]

    report = TolerantReconciler.run(config, left, right)

    [entry] = report.matched
    assert entry.differences == %{note: %{left: "l", right: "r", rule: :exact}}
  end
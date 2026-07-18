  test "a repeated composite key collapses to one matched pair" do
    config = config!(key_fields: [:org_id, :user_id])

    left = [
      %{org_id: 1, user_id: 10, score: 1},
      %{org_id: 1, user_id: 10, score: 2},
      %{org_id: 1, user_id: 20, score: 3}
    ]

    right = [%{org_id: 1, user_id: 10, score: 2}, %{org_id: 1, user_id: 20, score: 3}]

    report = TolerantReconciler.run(config, left, right)

    assert length(report.matched) == 2
    assert Enum.all?(report.matched, &(&1.differences == %{}))
  end
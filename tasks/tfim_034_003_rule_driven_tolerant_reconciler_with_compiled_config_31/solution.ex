  test "ignore rule wins even when the field is listed in compare_fields" do
    config =
      config!(key_fields: [:id], compare_fields: [:synced_at], rules: [synced_at: :ignore])

    report =
      TolerantReconciler.run(config, [%{id: 1, synced_at: "t1"}], [%{id: 1, synced_at: "t2"}])

    [entry] = report.matched
    assert entry.differences == %{}
  end
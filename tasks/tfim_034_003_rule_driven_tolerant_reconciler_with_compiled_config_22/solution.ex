  test "a compared field missing from one record is treated as nil" do
    config = config!(key_fields: [:id])
    report = TolerantReconciler.run(config, [%{id: 1, score: 42}], [%{id: 1}])

    [entry] = report.matched
    assert entry.differences == %{score: %{left: 42, right: nil, rule: :exact}}
  end
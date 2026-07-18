  test "numeric rule absorbs differences within tolerance" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0.01}])

    report =
      TolerantReconciler.run(config, [%{id: 1, amount: 100.0}], [%{id: 1, amount: 100.005}])

    [entry] = report.matched
    assert entry.differences == %{}
  end
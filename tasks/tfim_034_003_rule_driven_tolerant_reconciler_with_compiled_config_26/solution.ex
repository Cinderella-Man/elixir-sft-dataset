  test "numeric rule with zero tolerance still matches equal numbers" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0}])

    report = TolerantReconciler.run(config, [%{id: 1, amount: 7}], [%{id: 1, amount: 7}])

    [entry] = report.matched
    assert entry.differences == %{}
  end
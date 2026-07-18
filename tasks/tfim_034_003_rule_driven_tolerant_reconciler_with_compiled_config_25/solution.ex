  test "numeric rule falls back to equality when a value is not a number" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 5}])

    report = TolerantReconciler.run(config, [%{id: 1, amount: 10}], [%{id: 1, amount: nil}])

    [entry] = report.matched
    assert entry.differences == %{amount: %{left: 10, right: nil, rule: {:numeric, 5}}}
  end
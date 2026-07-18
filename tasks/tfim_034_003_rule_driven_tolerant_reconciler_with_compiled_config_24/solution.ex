  test "numeric rule reports differences beyond tolerance with the rule attached" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0.01}])

    report =
      TolerantReconciler.run(config, [%{id: 1, amount: 100.0}], [%{id: 1, amount: 100.5}])

    [entry] = report.matched

    assert entry.differences == %{
             amount: %{left: 100.0, right: 100.5, rule: {:numeric, 0.01}}
           }
  end
  test "compile rejects a numeric rule with a bad tolerance" do
    assert TolerantReconciler.compile(key_fields: [:id], rules: [amount: {:numeric, -1}]) ==
             {:error, {:invalid_rule, :amount}}

    assert TolerantReconciler.compile(key_fields: [:id], rules: [amount: {:numeric, "0.1"}]) ==
             {:error, {:invalid_rule, :amount}}
  end
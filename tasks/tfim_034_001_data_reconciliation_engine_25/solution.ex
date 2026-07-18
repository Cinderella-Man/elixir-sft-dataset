  test "a :key_fields list containing non-atoms raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], key_fields: ["id"])
    end
  end
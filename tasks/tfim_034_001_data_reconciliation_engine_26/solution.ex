  test "a nil :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], key_fields: nil)
    end
  end
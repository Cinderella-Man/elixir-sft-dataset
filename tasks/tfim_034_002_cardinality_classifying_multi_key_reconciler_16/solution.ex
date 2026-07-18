  test "empty key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      MultiKeyReconciler.classify([], [], key_fields: [])
    end
  end
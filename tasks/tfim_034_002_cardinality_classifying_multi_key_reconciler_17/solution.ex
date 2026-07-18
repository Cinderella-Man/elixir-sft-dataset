  test "non-atom key_fields raise ArgumentError" do
    assert_raise ArgumentError, fn ->
      MultiKeyReconciler.classify([], [], key_fields: ["id"])
    end
  end
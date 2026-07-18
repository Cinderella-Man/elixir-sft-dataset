  test "missing key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn -> MultiKeyReconciler.classify([], [], []) end
  end
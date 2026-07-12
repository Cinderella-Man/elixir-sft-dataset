  test "missing key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn -> StreamReconciler.start_link([]) end
  end
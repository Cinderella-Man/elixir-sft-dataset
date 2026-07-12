  test "invalid key_fields raise ArgumentError" do
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: []) end
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: ["id"]) end
  end
  test "non-list key_fields raise ArgumentError" do
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: :id) end
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: nil) end
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: [:id, "org"]) end
  end
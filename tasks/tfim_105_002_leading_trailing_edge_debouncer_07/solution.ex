  test "different keys are independent" do
    EdgeDebouncer.call("a", 100, notify({:key, "a"}), edge: :leading)
    EdgeDebouncer.call("b", 100, notify({:key, "b"}))

    assert_receive {:key, "a"}, 100
    assert_receive {:key, "b"}, 400
  end
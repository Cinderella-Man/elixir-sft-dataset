  test "different keys are independent" do
    Debouncer.call("a", 100, notify({:key, "a"}))
    Debouncer.call("b", 100, notify({:key, "b"}))

    assert_receive {:key, "a"}, 400
    assert_receive {:key, "b"}, 400
  end
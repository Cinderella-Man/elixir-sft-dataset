  test "different keys are independent" do
    MaxWaitDebouncer.call("a", 100, 1000, notify({:key, "a"}))
    MaxWaitDebouncer.call("b", 100, 1000, notify({:key, "b"}))

    assert_receive {:key, "a"}, 400
    assert_receive {:key, "b"}, 400
  end
  test "a fresh call after firing starts a new max-wait window" do
    MaxWaitDebouncer.call("k", 100, 1000, notify(:first))
    assert_receive :first, 400

    MaxWaitDebouncer.call("k", 100, 1000, notify(:second))
    assert_receive :second, 400
  end
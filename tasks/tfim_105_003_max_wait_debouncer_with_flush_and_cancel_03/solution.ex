  test "does not run before the delay elapses" do
    MaxWaitDebouncer.call("k", 200, 1000, notify(:done))
    refute_receive :done, 120
    assert_receive :done, 400
  end
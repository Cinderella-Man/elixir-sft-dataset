  test "trailing edge does not run before the delay elapses" do
    EdgeDebouncer.call("k", 200, notify(:done))
    refute_receive :done, 120
    assert_receive :done, 400
  end